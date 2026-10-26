// Crash, hang and error reports, without a third-party SDK.
//
// MetricKit hands the app Apple's own diagnostic reports (crashes, hangs, CPU and disk
// exceptions, slow launches) on the next launch. Each one goes to the server's ops log
// (`report_client_error`, capped at 30 an hour per person), together with unexpected
// server failures from Backend.rpc. Reports made while signed out wait on disk (the ten
// newest) and go once there's a session. Nothing personal is attached: build, iOS
// version and the report itself.
import Foundation
import MetricKit
import Supabase
import UIKit

final class Diagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = Diagnostics()

    private let queueKey = "jur.diagnostics.pending"
    private let lock = NSLock()

    /// Call once at launch.
    func start() {
        MXMetricManager.shared.add(self)
        Task { await flush() }
    }

    // MARK: MetricKit

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            for d in payload.crashDiagnostics ?? [] {
                let what = [d.exceptionType.map { "exception \($0)" }, d.signal.map { "signal \($0)" },
                            d.terminationReason].compactMap { $0 }.joined(separator: ", ")
                enqueue("crash", what.isEmpty ? "crash" : what, d.jsonRepresentation())
            }
            for d in payload.hangDiagnostics ?? [] {
                enqueue("hang", "hang \(Int(d.hangDuration.converted(to: .seconds).value)) s", d.jsonRepresentation())
            }
            for d in payload.cpuExceptionDiagnostics ?? [] {
                enqueue("cpu", "CPU exception", d.jsonRepresentation())
            }
            for d in payload.diskWriteExceptionDiagnostics ?? [] {
                enqueue("disk", "disk write exception", d.jsonRepresentation())
            }
            for d in payload.appLaunchDiagnostics ?? [] {
                enqueue("launch", "slow launch \(Int(d.launchDuration.converted(to: .seconds).value)) s", d.jsonRepresentation())
            }
        }
        Task { await flush() }
    }

    // MARK: server errors

    /// An error the person didn't cause and we didn't expect: a database exception, a reply
    /// the app couldn't decode. Being offline, a cancelled request or a rate limit isn't one.
    func report(_ error: Error, in function: String) {
        if error is CancellationError || error is URLError { return }
        let text = String(describing: error)
        let lower = text.lowercased()
        if lower.contains("rate_limited") || lower.contains("cancelled") || lower.contains("jwt") { return }
        // Expected answers the screens handle themselves.
        if lower.contains("not_found") || lower.contains("duplicate") { return }
        enqueue("error", "\(function): \(String(text.prefix(300)))", nil)
        Task { await flush() }
    }

    // MARK: queue

    private struct Pending: Codable {
        let kind: String
        let message: String
        let detail: String?
        let at: Date
    }

    private func enqueue(_ kind: String, _ message: String, _ json: Data?) {
        // Keep reports small: the server truncates anything past 16 kB anyway.
        let detail = json.flatMap { String(data: $0.prefix(15_000), encoding: .utf8) }
        lock.lock(); defer { lock.unlock() }
        var list = load()
        list.append(Pending(kind: kind, message: String(message.prefix(400)), detail: detail, at: .now))
        save(Array(list.suffix(10)))
    }

    private func load() -> [Pending] {
        guard let data = UserDefaults.standard.data(forKey: queueKey) else { return [] }
        return (try? JSONDecoder().decode([Pending].self, from: data)) ?? []
    }

    private func save(_ list: [Pending]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: queueKey)
    }

    private func take() -> [Pending] {
        lock.lock(); defer { lock.unlock() }
        let list = load()
        save([])
        return list
    }

    /// Sends what's waiting. Straight to the client (not through Backend.rpc), so a failing
    /// report can never report itself.
    func flush() async {
        guard supabase.auth.currentUser != nil else { return }
        let list = take()
        guard !list.isEmpty else { return }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let os = await MainActor.run { UIDevice.current.systemVersion }
        var failed: [Pending] = []
        for p in list {
            var detail: [String: AnyJSON] = [
                "build": .string(build), "version": .string(version), "ios": .string(os),
                "at": .string(ISO8601DateFormatter().string(from: p.at)),
            ]
            if let d = p.detail { detail["report"] = .string(d) }
            do {
                try await supabase.rpc("report_client_error", params: [
                    "p_kind": .string(p.kind), "p_message": .string(p.message), "p_detail": .object(detail),
                ]).execute()
            } catch {
                failed.append(p)
            }
        }
        // Offline: keep them for next time.
        if !failed.isEmpty {
            lock.lock(); defer { lock.unlock() }
            save(Array((failed + load()).suffix(10)))
        }
    }
}
