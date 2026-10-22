// The end of the deck: say so, then offer ways to see more people. Each suggestion
// shows exactly what it changes ("Ages 20–45") and only appears when it would help.
import SwiftUI

struct DiscoverEmpty: View {
    /// Reloads the deck and says how many people it found.
    let reload: () async -> Int
    var openEvents: (() -> Void)?

    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @State private var busy = false
    @State private var travel = false

    private var profile: MyProfile? { session.profile }
    private var ageMin: Int { profile?.ageMin ?? 18 }
    private var ageMax: Int { profile?.ageMax ?? 60 }
    /// The range one step wider: five years each way, within 18–99.
    private var wider: (min: Int, max: Int) { (max(18, ageMin - 5), min(99, ageMax + 5)) }
    private var canWidenAge: Bool { wider.min != ageMin || wider.max != ageMax }
    /// Only people looking for dates are offered training partners; "both" already sees everyone.
    private var canAddBuddies: Bool { (profile?.mode ?? .dating) == .dating }

    private var city: String {
        guard let p = profile else { return "" }
        if let c = p.travelCity, let until = p.travelUntil.flatMap({ Date.iso($0) }), until > .now {
            return Cities.label(c)
        }
        return Cities.label(p.city)
    }

    var body: some View {
        VStack(spacing: Sp.xl) {
            VStack(spacing: Sp.sm) {
                Image(systemName: "figure.run")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(Color.q.muted)
                    .accessibilityHidden(true)
                Text(t("discover.empty")).qText(.title3).foregroundStyle(Color.q.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(t(Config.eventsEnabled ? "discover.emptySub" : "discover.emptySubApp"))
                    .qText(.callout).foregroundStyle(Color.q.inkSoft)
                    .multilineTextAlignment(.center)
                if let openEvents, Config.eventsEnabled {
                    Button(t("discover.seeEvents"), action: openEvents)
                        .buttonStyle(.q(.primary, compact: true))
                        .fixedSize()
                        .padding(.top, Sp.xs)
                }
            }
            .padding(.top, Sp.xxl)

            widenCard
        }
        .frame(maxWidth: .infinity)
        .navigationDestination(isPresented: $travel) { TravelView() }
    }

    private var widenCard: some View {
        VStack(alignment: .leading, spacing: Sp.md) {
            VStack(alignment: .leading, spacing: Sp.xxs) {
                Text(t("empty.widenTitle")).qText(.headline).foregroundStyle(Color.q.ink)
                Text(t("empty.lookingNow", ["min": ageMin, "max": ageMax, "city": city]))
                    .qText(.footnote).foregroundStyle(Color.q.muted)
            }
            VStack(spacing: Sp.sm) {
                if canWidenAge {
                    option(t("empty.widenAge", ["min": wider.min, "max": wider.max]), symbol: "arrow.left.and.right") {
                        try await Backend.setAgeRange(userId: $0, min: wider.min, max: wider.max)
                    }
                }
                if canAddBuddies {
                    option(t("empty.addBuddies"), symbol: "figure.2") {
                        try await Backend.setMode(userId: $0, .both)
                    }
                }
                Button { travel = true } label: {
                    row(t("empty.otherCity"), symbol: "airplane", trailing: "chevron.right")
                }
                .buttonStyle(QPressStyle())
            }
        }
        .padding(Sp.lg)
        .background(Color.q.card, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .disabled(busy)
    }

    /// One tap applies the change, refreshes the profile and the deck, then says what came of it.
    private func option(_ title: String, symbol: String, apply: @escaping (UUID) async throws -> Void) -> some View {
        Button {
            Task {
                guard let id = session.userId, !busy else { return }
                busy = true
                defer { busy = false }
                Haptics.tick()
                do {
                    try await apply(id)
                    await session.refreshProfile()
                    let found = await reload()
                    toasts.show(t(found > 0 ? "empty.widened" : "empty.widenedNone"))
                } catch {
                    toasts.show(t("common.error"), error: true)
                }
            }
        } label: {
            row(title, symbol: symbol, trailing: "plus")
        }
        .buttonStyle(QPressStyle())
    }

    private func row(_ title: String, symbol: String, trailing: String) -> some View {
        HStack(spacing: Sp.md) {
            Image(systemName: symbol)
                .font(.q(.callout))
                .foregroundStyle(Color.q.blueText)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(title).qText(.callout).foregroundStyle(Color.q.ink)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: trailing)
                .font(.q(.footnote).weight(.semibold))
                .foregroundStyle(Color.q.hint)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Sp.md)
        .frame(minHeight: Layout.rowMin)
        .background(Color.q.bg, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .contentShape(Rectangle())
    }
}
