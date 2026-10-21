// Empty, error and loading states, built on the system's ContentUnavailableView.
import SwiftUI

struct ErrorStateView: View {
    enum Kind { case offline, server }
    var kind: Kind = .server
    var title: String?
    var message: String?
    var retry: (() async -> Void)?
    /// A second, quieter way out (e.g. Sign out when the profile can't load).
    var secondary: (title: String, action: () async -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title ?? t(kind == .offline ? "states.offlineTitle" : "states.errorTitle"),
                  systemImage: kind == .offline ? "wifi.slash" : "exclamationmark.triangle")
                .font(.q(.title3))
        } description: {
            Text(message ?? t(kind == .offline ? "states.offlineSub" : "states.errorSub"))
        } actions: {
            if let retry {
                Button(t("common.retry")) { Task { await retry() } }
                    .buttonStyle(.q(.primary, compact: true))
                    .fixedSize()
            }
            if let secondary {
                Button(secondary.title) { Task { await secondary.action() } }
                    .buttonStyle(.q(.ghost, compact: true))
                    .fixedSize()
            }
        }
        .background(Color.q.bg)
    }

    /// Picks offline vs server from the error itself.
    static func kind(for error: Error) -> Kind {
        (error as? URLError).map { [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost].contains($0.code) } == true
            ? .offline : .server
    }
}

/// Empty states: the system layout with the brand title face and exactly one next step.
/// Prefer an in-metaphor empty state where one exists (the empty board, blank stamp slots).
struct QEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol).font(.q(.title3))
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.q(.primary, compact: true))
                    .fixedSize()
            }
        }
        .background(Color.q.bg)
    }
}

/// Full-screen launch only. Inside a screen use `ProgressView()` or skeleton rows
/// (`.redacted(reason: .placeholder)`); `DotsMeeting` belongs to the match moment.
struct LoadingView: View {
    var body: some View {
        MarkLoader()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.q.bg)
    }
}

/// The translated legal line with working Terms and Privacy links.
struct LegalFooter: View {
    let leadKey: String
    var onBlue = false

    private var attributed: AttributedString {
        let lead = t(leadKey)
        let terms = t("legal.terms"), privacy = t("legal.privacy")
        var text = AttributedString("\(lead) \(terms) · \(privacy)")
        if let r = text.range(of: terms) { text[r].link = Config.termsURL; text[r].underlineStyle = .single }
        if let r = text.range(of: privacy, options: .backwards) { text[r].link = Config.privacyURL; text[r].underlineStyle = .single }
        return text
    }

    var body: some View {
        Text(attributed)
            .font(.q(.caption))
            .fontWeight(.medium)
            .multilineTextAlignment(.center)
            .foregroundStyle(onBlue ? Color.white.opacity(0.8) : Color.q.muted)
            .tint(onBlue ? .white : Color.q.blueText)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}
