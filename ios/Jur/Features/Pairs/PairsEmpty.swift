// No matches yet: how many people you've liked so far, then what would make your
// profile stronger. Each unfinished item opens the screen that fixes it.
import SwiftUI

struct PairsEmpty: View {
    var goDiscover: () -> Void

    @Environment(SessionStore.self) private var session
    /// nil until loaded, or if the server doesn't have the count yet: the line is hidden.
    @State private var likesSent: Int?
    @State private var hasPrompts = false
    @State private var opened: ProfileStrength.Kind?

    var body: some View {
        ScrollView {
            VStack(spacing: Sp.xl) {
                VStack(spacing: Sp.sm) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(Color.q.muted)
                        .accessibilityHidden(true)
                    Text(t("matches.empty")).qText(.title3).foregroundStyle(Color.q.ink)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    if let n = likesSent, n > 0 {
                        Text(t("empty.likesSent", ["n": n])).qText(.headline).foregroundStyle(Color.q.blueText)
                            .contentTransition(.numericText())
                        Text(t("empty.likesSentSub")).qText(.callout).foregroundStyle(Color.q.inkSoft)
                            .multilineTextAlignment(.center)
                    } else {
                        Text(t("matches.emptySubApp")).qText(.callout).foregroundStyle(Color.q.inkSoft)
                            .multilineTextAlignment(.center)
                    }
                    Button(t("matches.goDiscover"), action: goDiscover)
                        .buttonStyle(.q(.primary, compact: true))
                        .fixedSize()
                        .padding(.top, Sp.xs)
                }
                .padding(.top, Sp.xxl)

                if let p = session.profile {
                    ProfileStrengthCard(strength: ProfileStrength(profile: p, hasPrompts: hasPrompts)) { opened = $0 }
                }
            }
            .padding(.horizontal, Layout.margin)
            .padding(.bottom, Sp.xl)
        }
        .background(Color.q.bg)
        .navigationDestination(item: $opened) { $0.destination }
        .task { await load() }
    }

    private func load() async {
        async let sent = try? Backend.likesSent()
        if let id = session.userId, let card = try? await Backend.profile(id) {
            hasPrompts = !(card.prompts ?? []).isEmpty
        }
        let n = await sent
        withMotion(Motion.smooth) { likesSent = n }
    }
}
