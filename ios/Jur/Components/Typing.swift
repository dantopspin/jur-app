// Typing, everywhere in the app:
// - a tap anywhere outside a text field puts the keyboard away (taps still reach buttons);
//   places that must keep it up while tapped (the chat composer) mark themselves;
// - Return moves to the next field, also in fields that wrap onto several lines;
// - counters appear as a limit gets near;
// - drafts survive leaving a screen.
import SwiftUI
import UIKit

// MARK: tap outside to dismiss

@MainActor
final class KeyboardDismisser: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismisser()
    private var installed: Set<ObjectIdentifier> = []
    /// Window-space rects where a tap must not put the keyboard away.
    fileprivate var keepAreas: [UUID: CGRect] = [:]

    /// Adds the recogniser to every window of the app (sheets live in the same window).
    func install() {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        for window in windows where !installed.contains(ObjectIdentifier(window)) {
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            installed.insert(ObjectIdentifier(window))
        }
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        g.view?.endEditing(true)
    }

    nonisolated func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        MainActor.assumeIsolated {
            var view = touch.view
            while let v = view {
                if v is UITextField || v is UITextView || v is UISearchBar { return false }
                view = v.superview
            }
            guard let window = touch.window else { return true }
            let point = touch.location(in: window)
            return !keepAreas.values.contains { $0.contains(point) }
        }
    }

    nonisolated func gestureRecognizer(_ g: UIGestureRecognizer,
                                       shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

extension View {
    /// Taps here keep the keyboard up (the chat composer: tapping Send keeps typing going).
    func keepsKeyboard() -> some View { modifier(KeepsKeyboard()) }

    /// Return finishes this field and calls `next` (focus the next field, or submit).
    /// Works for fields with `axis: .vertical` too, where Return would otherwise add a line.
    func returnGoesNext(_ text: Binding<String>, _ next: @escaping () -> Void) -> some View {
        onChange(of: text.wrappedValue) { _, new in
            guard new.contains("\n") else { return }
            text.wrappedValue = new.replacingOccurrences(of: "\n", with: "")
            next()
        }
        .onSubmit(next)
    }

    /// Cuts text at `limit` characters as it's typed (pasted text too).
    func limited(_ text: Binding<String>, to limit: Int) -> some View {
        onChange(of: text.wrappedValue) { _, new in
            if new.count > limit { text.wrappedValue = String(new.prefix(limit)) }
        }
    }
}

private struct KeepsKeyboard: ViewModifier {
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { g in
                    Color.clear
                        .onAppear { KeyboardDismisser.shared.keepAreas[id] = g.frame(in: .global) }
                        .onChange(of: g.frame(in: .global)) { _, f in KeyboardDismisser.shared.keepAreas[id] = f }
                }
            }
            .onDisappear { KeyboardDismisser.shared.keepAreas[id] = nil }
    }
}

// MARK: counters

/// "138/140": shown from 80% of the limit, clay at the limit. Quiet the rest of the time.
struct CharCounter: View {
    let count: Int
    let limit: Int

    var body: some View {
        if Double(count) >= Double(limit) * 0.8 {
            Text(verbatim: "\(count)/\(limit)")
                .qText(.caption)
                .monospacedDigit()
                .foregroundStyle(count >= limit ? Color.q.clay : Color.q.muted)
                .contentTransition(.numericText())
                .animation(Motion.adaptive(Motion.snappy), value: count)
                .transition(.opacity)
                .accessibilityLabel(t("typing.left", ["n": max(limit - count, 0)]))
        }
    }
}

// MARK: drafts

/// Unsent text, kept per place ("chat.<match>", "note.<profile>") across leaving the screen
/// and relaunching. Cleared when sent, and on sign-out.
enum Drafts {
    private static let key = "jur.drafts"

    static func get(_ id: String) -> String {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: String])?[id] ?? ""
    }

    static func set(_ id: String, _ text: String) {
        var all = (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        all[id] = trimmed.isEmpty ? nil : text
        UserDefaults.standard.set(all, forKey: key)
    }

    static func clearAll() { UserDefaults.standard.removeObject(forKey: key) }
}

// MARK: errors

/// Says what went wrong in words a person can act on, instead of a generic "error".
func errorText(_ error: Error) -> String {
    if let e = error as? URLError {
        switch e.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return t("err.offline")
        case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return t("err.slow")
        default: break
        }
    }
    if let e = error as? ServerError {
        let key = "err.\(e.code)"
        if t(key) != key { return t(key) }
    }
    let text = String(describing: error).lowercased()
    if text.contains("jwt") || text.contains("not authenticated") || text.contains("401") { return t("err.session") }
    if text.contains("payload too large") || text.contains("413") { return t("err.tooBig") }
    return t("err.generic")
}

extension ToastCenter {
    func show(_ error: Error) { show(errorText(error), error: true) }
}
