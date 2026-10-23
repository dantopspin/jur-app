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

/// The translated legal line: "<lead> Terms · Privacy" with working links, plus an optional
/// trailing sentence ("18+ only."). The lead never names the documents itself.
struct LegalFooter: View {
    let leadKey: String
    var trailingKey: String?
    var onBlue = false

    private var attributed: AttributedString {
        let terms = t("legal.terms"), privacy = t("legal.privacy")
        var text = AttributedString("\(t(leadKey)) ")
        var termsPart = AttributedString(terms)
        termsPart.link = Config.termsURL
        termsPart.underlineStyle = .single
        var privacyPart = AttributedString(privacy)
        privacyPart.link = Config.privacyURL
        privacyPart.underlineStyle = .single
        text += termsPart
        text += AttributedString(" · ")
        text += privacyPart
        if let trailingKey { text += AttributedString(". " + t(trailingKey)) }
        return text
    }

    var body: some View {
        Text(attributed)
            .font(.q(.caption))
            .fontWeight(.medium)
            .multilineTextAlignment(.center)
            .foregroundStyle(onBlue ? Color.q.blueMist : Color.q.muted)
            .tint(onBlue ? .white : Color.q.blueText)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

// MARK: loading

/// Shows its content only if still on screen after a blink (350 ms), fading in. Most answers
/// arrive sooner, and then no placeholder ever flashes. Use it around skeletons.
struct AfterABlink<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var shown = false

    var body: some View {
        ZStack {
            if shown { content().transition(.opacity) }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.adaptive(Motion.fade)) { shown = true }
        }
    }
}

/// List rows while a list loads: a round photo and two lines, like the rows that follow.
struct SkeletonRows: View {
    var count = 4
    var photo: CGFloat = 52

    var body: some View {
        VStack(spacing: Sp.lg) {
            ForEach(0..<count, id: \.self) { i in
                HStack(spacing: Sp.md) {
                    Circle().fill(Color.q.line).frame(width: photo, height: photo)
                    VStack(alignment: .leading, spacing: Sp.sm) {
                        Capsule().fill(Color.q.line).frame(width: 120, height: 12)
                        Capsule().fill(Color.q.line).frame(width: i.isMultiple(of: 2) ? 200 : 160, height: 10)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(Layout.margin)
        .qShimmer()
        .accessibilityHidden(true)
    }
}

/// Photo tiles while a grid loads (Likes).
struct SkeletonTiles: View {
    var count = 4
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Sp.md), count: 2)

    var body: some View {
        LazyVGrid(columns: columns, spacing: Sp.md) {
            ForEach(0..<count, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Color.q.line)
                    .aspectRatio(3 / 4, contentMode: .fit)
            }
        }
        .padding(Layout.margin)
        .qShimmer()
        .accessibilityHidden(true)
    }
}
