// Today's picks: five people chosen for what you share, refreshed every evening.
import SwiftUI

struct PicksView: View {
    @Environment(ToastCenter.self) private var toasts
    @State private var picks: [ProfileCard]? = DataCache.get(CacheKey.picks(Backend.today), as: [ProfileCard].self)
    @State private var decided: [UUID: SwipeKind] = [:]
    @State private var paywall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Sp.lg) {
                Text(t(Config.eventsEnabled ? "picks.sub" : "picks.subApp")).qText(.callout).foregroundStyle(Color.q.inkSoft)
                if let picks {
                    if picks.isEmpty {
                        QEmptyState(symbol: "sparkles", title: t("picks.empty"), message: t("picks.emptySub")).frame(minHeight: 360)
                    }
                    ForEach(picks) { p in
                        VStack(spacing: Sp.md) {
                            NavigationLink { ProfileView(id: p.id, initial: p) } label: { ProfileCardView(card: p, compact: true) }
                                .buttonStyle(.plain)
                            if let d = decided[p.id] {
                                QTag(label: t(d == .pass ? "picks.passed" : "picks.liked"), tone: d == .pass ? .neutral : .good)
                                    .transition(.qPop)
                            } else {
                                HStack(spacing: Sp.md) {
                                    Button(t("discover.pass")) { Task { await decide(p, .pass) } }.buttonStyle(.q(.secondary, compact: true))
                                    Button(t("discover.like")) { Task { await decide(p, .like) } }.buttonStyle(.q(.primary, compact: true))
                                }
                                .transition(.opacity)
                            }
                        }
                    }
                } else {
                    AfterABlink {
                        ProfileCardView(card: .placeholder, compact: true).redacted(reason: .placeholder).qShimmer()
                    }
                }
            }
            .padding(Layout.margin)
        }
        .background(Color.q.bg)
        .navigationTitle(t("picks.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Today's saved picks show at once; the server's answer replaces them quietly.
            if let fresh = try? await Backend.dailyPicks() { withMotion(Motion.fade) { picks = fresh } }
            else if picks == nil { picks = [] }
        }
        .sheet(isPresented: $paywall) { PaywallView(context: .outOfLikes) }
    }

    private func decide(_ p: ProfileCard, _ kind: SwipeKind) async {
        do {
            let r = try await Backend.swipe(p.id, kind)
            if r.ok {
                withMotion(Motion.bouncy) { decided[p.id] = kind }
                if kind == .like { Haptics.success() }
                if r.matchId != nil { toasts.show(t("match.title")) }
            } else if r.error == "like_limit" { paywall = true }
        } catch { toasts.show(t("common.error"), error: true) }
    }
}

/// The boost: 30 minutes at the top of Discover. Free once a week for Pro, or from credits.
struct BoostButton: View {
    /// The round 48 pt button in Discover's action bar (otherwise a bar icon).
    var round = false
    let onNeedPro: () -> Void
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @State private var busy = false

    private var boostedUntil: Date? {
        session.limits?.boostedUntil.flatMap { Date.iso($0) }.flatMap { $0 > .now ? $0 : nil }
    }
    private var available: Int {
        (session.limits?.boostCredits ?? 0) + (session.limits?.freeBoostAvailable == true ? 1 : 0)
    }

    var body: some View {
        Button { Task { await boost() } } label: {
            Image(systemName: boostedUntil != nil || round ? "bolt.fill" : "bolt")
                .font(round ? .system(size: 18, weight: .bold) : nil)
                .foregroundStyle(boostedUntil != nil ? Color.q.gold : Color.q.blueText)
                .contentTransition(.symbolEffect(.replace))
                // While a boost runs, the bolt breathes: it means "you're at the top now".
                .symbolEffect(.pulse, options: .repeating, isActive: boostedUntil != nil)
                .overlay(alignment: .topTrailing) {
                    if available > 0 && boostedUntil == nil {
                        Text("\(available)").font(.q(.label)).foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .padding(.horizontal, Sp.xs).background(Color.q.blue, in: Capsule())
                            .offset(x: 10, y: -8)
                    }
                }
                .frame(width: round ? 48 : nil, height: round ? 48 : nil)
                .background { if round { Circle().fill(Color.q.card).qElevated() } }
        }
        .buttonStyle(.qPress)
        .disabled(busy)
        .accessibilityLabel(boostedUntil.map { t("discover.boostActive", ["time": Fmt.time($0)]) } ?? t("discover.boost"))
    }

    private func boost() async {
        if let until = boostedUntil { toasts.show(t("discover.boostActive", ["time": Fmt.time(until)])); return }
        busy = true
        defer { busy = false }
        do {
            let r = try await Backend.boost()
            if r.ok {
                Haptics.success()
                toasts.show(t("discover.boostDone"), symbol: "bolt.fill")
                await session.refreshLimits()
            } else if session.limits?.pro == true {
                toasts.show(t("discover.noBoosts"), error: true)
            } else {
                onNeedPro()
            }
        } catch { toasts.show(t("common.error"), error: true) }
    }
}
