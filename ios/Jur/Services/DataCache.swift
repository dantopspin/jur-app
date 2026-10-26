// The last answer of a few server calls, kept on the phone per account, so screens draw
// at once (on launch, on a tab switch) and refresh behind. Raw JSON is stored and decoded
// with the same decoder as live answers, so the cache always reads like the server.
import Foundation
import Supabase

enum DataCache {
    private static let queue = DispatchQueue(label: "kz.jur.datacache", qos: .utility)

    private static var root: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("jur-data", isDirectory: true)
    }

    private static func file(_ key: String) -> URL? {
        guard let user = Backend.me else { return nil }
        return root.appendingPathComponent(user.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(key + ".json")
    }

    static func put(_ data: Data, _ key: String) {
        guard let url = file(key) else { return }
        queue.async {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Small files (a few KB), read synchronously so the first frame already has them.
    static func get<T: Decodable>(_ key: String, as type: T.Type = T.self) -> T? {
        guard let url = file(key), let data = try? Data(contentsOf: url) else { return nil }
        return try? Backend.decoder.decode(T.self, from: data)
    }

    /// Signing out: nothing of this account stays on the phone.
    static func clearAll() {
        let dir = root
        queue.async { try? FileManager.default.removeItem(at: dir) }
    }
}

enum CacheKey {
    static let me = "me"
    static let card = "card"
    static let limits = "limits"
    static let events = "events"
    static let matches = "matches"
    static let likes = "likes"
    static func picks(_ day: String) -> String { "picks-\(day)" }
}

extension Backend {
    /// A database function whose answer is also kept for next time under `key`.
    static func rpc<T: Decodable>(_ fn: String, _ params: [String: AnyJSON] = [:], cacheAs key: String,
                                  as type: T.Type = T.self) async throws -> T {
        do {
            let response = try await supabase.rpc(fn, params: params).execute()
            let value = try decoder.decode(T.self, from: response.data)
            DataCache.put(response.data, key)
            return value
        } catch {
            Diagnostics.shared.report(error, in: fn)
            throw error
        }
    }
}
