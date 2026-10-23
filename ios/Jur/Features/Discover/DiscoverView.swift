// Discover: tonight's departures on top, then one person at a time.
// Pass / like by button or swipe; long-press like (or the note button) for a like with a note.
import SwiftUI

@MainActor
@Observable
final class DiscoverModel {
    var queue: [ProfileCard] = []
    /// Today's events: last time's list first (no board popping in above the card later).
    var tonight: [EventItem] = DiscoverModel.todays(DataCache.get(CacheKey.events, as: [EventItem].self) ?? [])
    /// The skeleton card: only on the first load, and only once it has taken a moment,
    /// so an empty or fast answer never flashes a grey card first.
    var loading = false
    private(set) var loaded = false
    var failed = false
    var match: (card: ProfileCard, matchId: UUID)?
    var paywall = false
    var paywallContext: PaywallContext = .outOfLikes

    var current: ProfileCard? { queue.first }

    func load() async {
        failed = false
        let skeleton = loaded ? nil : Task {
            try? await Task.sleep(for: .milliseconds(350))
            if !Task.isCancelled { loading = true }
        }
        // People and events load side by side; the card shows as soon as people arrive.
        async let events: [EventItem]? = Config.eventsEnabled ? (try? await Backend.upcomingEvents()) : []
        do {
            queue = try await Backend.discover()
            prefetchNext()
        } catch {
            failed = queue.isEmpty
        }
        skeleton?.cancel()
        loading = false
        loaded = true
        if let e = await events { tonight = Self.todays(e) }
    }

    /// Filters changed: start the deck over (the skeleton shows only if it takes a moment).
    func reload() async {
        queue = []
        loaded = false
        await load()
    }

    /// The next cards' photos load while you look at this one.
    private func prefetchNext() {
        ImageLoader.shared.prefetch(queue.prefix(3).flatMap(\.photoURLs), .full)
    }

    static func todays(_ events: [EventItem]) -> [EventItem] {
        events.filter { Fmt.calendar.isDateInToday($0.start) && $0.end > .now }.sorted { $0.start < $1.start }
    }

    /// The card that just came back (undo, a rolled-back like) and the side it returns from.
    var returningId: UUID?
    var returningEdge: Edge = .leading

    /// Optimistic: the card leaves at once (animated); on a limit it comes back and the paywall opens.
    func commit(_ kind: SwipeKind, note: String? = nil, toasts: ToastCenter) {
        guard let card = queue.first else { return }
        withMotion(Motion.smooth) { _ = queue.removeFirst() }
        prefetchNext()
        Task { await send(card, kind, note: note, toasts: toasts) }
    }

    private func send(_ card: ProfileCard, _ kind: SwipeKind, note: String?, toasts: ToastCenter) async {
        do {
            let r = try await Backend.swipe(card.id, kind, note: note)
            if !r.ok {
                restore(card, after: kind)
                switch r.error {
                case "like_limit": paywallContext = .outOfLikes; paywall = true
                case "super_limit": toasts.show(t("discover.superLimit"), error: true)
                default: toasts.show(t("common.error"), error: true)
                }
                return
            }
            if let id = r.matchId {
                match = (card, id)
                Haptics.success()
                Sounds.play(.match)
            } else if kind == .super || note != nil {
                Haptics.success()
            }
            if queue.count < 3 { await refill() }
        } catch {
            restore(card, after: kind)
            toasts.show(t("common.error"), error: true)
        }
    }

    /// Puts a card back on top, coming in from the side it left.
    private func restore(_ card: ProfileCard, after kind: SwipeKind) {
        returningId = card.id
        returningEdge = kind == .pass ? .leading : kind == .super ? .top : .trailing
        withMotion(Motion.bouncy) { queue.insert(card, at: 0) }
    }

    func undo(toasts: ToastCenter) async {
        do {
            let r = try await Backend.rewind()
            if let p = r.profile {
                returningId = p.id
                returningEdge = .leading
                withMotion(Motion.bouncy) { queue.insert(p, at: 0) }
                Haptics.bump()
                return
            }
            switch r.error {
            case "pro_only": paywallContext = .undo; paywall = true
            default: toasts.show(t("undo.nothing"))
            }
        } catch { toasts.show(t("common.error"), error: true) }
    }

    private func refill() async {
        guard let more = try? await Backend.discover() else { return }
        let have = Set(queue.map(\.id))
        let fresh = more.filter { !have.contains($0.id) }
        withMotion(Motion.smooth) { queue += fresh }
        prefetchNext()
    }
}

struct DiscoverView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(SportsCatalog.self) private var catalog
    @State private var model = DiscoverModel()
    @State private var noteFor: ProfileCard?
    @State private var dragging = false
    /// Bumped once a day so the picks icon bounces when there are new picks.
    @State private var picksBounce = 0
    #if DEBUG
    @State private var previewOnboarding = false
    #endif
    /// Right after onboarding the first card deals in and the buttons follow, once.
    @State private var dealt = !UserDefaults.standard.bool(forKey: "jur.firstRun")
    @AppStorage("jur.picksSeenDay") private var picksSeenDay = ""
    @State private var fling: DeckFling?
    @State private var openEvent: EventItem?
    @State private var showFilters = false
    @State private var boostPaywall = false
    @Binding var showPicks: Bool
    var openEvents: () -> Void = {}
    var openChat: (UUID) -> Void = { _ in }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Sp.md) {
                    if let p = session.profile {
                        Text(t(greetingKey(), ["name": p.name])).qText(.footnote).foregroundStyle(Color.q.inkSoft)
                            .qScrollDepth()
                    }
                    if !model.tonight.isEmpty {
                        DepartureBoard(departures: model.tonight.prefix(3).map(\.departure),
                                       header: t("board.today", ["city": Cities.label(session.profile?.city ?? "")]),
                                       seeAll: openEvents) { d in
                            openEvent = model.tonight.first { $0.id == d.id }
                        }
                        .qScrollDepth()
                    }
                    deck
                }
                .padding(.horizontal, Layout.margin)
                .padding(.bottom, 120)
            }
            .scrollDisabled(dragging)
            .background(Color.q.bg)
            .refreshable { await model.load() }
            .overlay(alignment: .bottom) { if model.current != nil { actions } }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The logo isn't a button: on iOS 26 it sits on the bar without a glass circle.
                ToolbarItem(placement: .topBarLeading) {
                    Lockup(size: 20)
                        .fixedSize()
                    #if DEBUG
                        // Debug builds only: triple-tap the logo to walk through onboarding.
                        .onTapGesture(count: 3) { previewOnboarding = true }
                    #endif
                }
                .qPlainBarItem()
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showPicks = true } label: {
                        Image(systemName: "sparkles")
                            .symbolEffect(.bounce, value: picksBounce)
                            .accessibilityLabel(t("picks.title"))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    FiltersButton(narrowed: session.profile.map { DiscoverFilters($0).narrowed } ?? false) { showFilters = true }
                }
            }
            .navigationDestination(item: $openEvent) { e in EventDetailView(eventId: e.id, initial: e) }
            .navigationDestination(isPresented: $showPicks) { PicksView() }
        }
        .task {
            if model.queue.isEmpty { await model.load() }
            // Today's events you joined: start their lock-screen countdowns.
            LiveDepartures.sync(model.tonight) { catalog.sport($0)?.emoji ?? "" }
        }
        .animation(Motion.adaptive(Motion.fade), value: model.loaded)
        .task {
            let today = Fmt.calendar.startOfDay(for: .now).formatted(.iso8601.year().month().day())
            guard picksSeenDay != today else { return }
            try? await Task.sleep(for: .seconds(0.8))
            picksBounce += 1
            picksSeenDay = today
        }
        .sheet(item: $noteFor) { card in
            NoteSheet(card: card) { note in fling = DeckFling(kind: .like, note: note) }
        }
        .sheet(isPresented: $model.paywall) { PaywallView(context: model.paywallContext) }
        .sheet(isPresented: $boostPaywall) { PaywallView(context: .boost) }
        .sheet(isPresented: $showFilters) {
            FiltersSheet { Task { await model.reload() } }
        }
        #if DEBUG
        .fullScreenCover(isPresented: $previewOnboarding) {
            OnboardingView(preview: true) { previewOnboarding = false }
        }
        #endif
        .fullScreenCover(isPresented: Binding(get: { model.match != nil }, set: { if !$0 { model.match = nil } })) {
            if let m = model.match {
                MatchMoment(other: m.card, myPhoto: session.profile?.photos.first) {
                    model.match = nil
                    openChat(m.matchId)
                } onKeep: { model.match = nil }
            }
        }
    }

    @ViewBuilder private var deck: some View {
        if !model.loaded && !model.loading {
            // The first answer is on its way: hold the space, show nothing yet.
            Color.clear.frame(height: 420)
        } else if model.loading {
            ProfileCardView(card: .placeholder, compact: true).redacted(reason: .placeholder).qShimmer()
        } else if model.failed {
            ErrorStateView(retry: { await model.load() }).frame(minHeight: 420)
        } else if !model.queue.isEmpty {
            SwipeDeck(cards: Array(model.queue.prefix(2)), dragging: $dragging, fling: $fling,
                      returningId: model.returningId, returningEdge: model.returningEdge,
                      onCommit: { kind, note in model.commit(kind, note: note, toasts: toasts) },
                      onNote: { noteFor = $0 })
                .opacity(dealt ? 1 : 0)
                .offset(y: dealt || Motion.reduceMotion ? 0 : 60)
                .onAppear {
                    guard !dealt else { return }
                    UserDefaults.standard.removeObject(forKey: "jur.firstRun")
                    withAnimation(Motion.adaptive(Motion.hero).delay(0.2)) { dealt = true }
                }
        } else {
            DiscoverEmpty(reload: {
                await model.load()
                return model.queue.count
            }, openEvents: openEvents)
        }
    }

    private var actions: some View {
        // Five, like the classic dating bar: undo, pass, super like, like, boost.
        HStack(spacing: Sp.md) {
            RoundAction(symbol: "arrow.uturn.backward", size: 48, label: t("undo.title")) {
                Task { await model.undo(toasts: toasts) }
            }
            RoundAction(symbol: "xmark", tint: Color.q.clay, size: 64, label: t("discover.pass")) { fling = DeckFling(kind: .pass) }
            RoundAction(symbol: "star.fill", tint: Color.q.onGold, fill: Color.q.gold, size: 48, label: t("discover.super")) {
                fling = DeckFling(kind: .super)
            }
            RoundAction(symbol: "heart.fill", tint: .white, fill: Color.q.blue, size: 64, label: t("discover.like")) { fling = DeckFling(kind: .like) }
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in noteFor = model.current })
            BoostButton(round: true) { boostPaywall = true }
        }
        .opacity(dealt ? 1 : 0)
        .scaleEffect(dealt || Motion.reduceMotion ? 1 : 0.8)
        .animation(Motion.adaptive(Motion.bouncy).delay(0.45), value: dealt)
        .padding(.bottom, Sp.lg)
    }

}

extension ProfileCard {
    /// Grey stand-in for skeletons.
    static let placeholder = ProfileCard(
        id: UUID(), memberNo: 42, name: "Айгерім", age: 27, city: "almaty", bio: nil, nextChallenge: nil,
        photos: [], verified: false, isHost: nil, eventsAttended: 3, sports: [CardSport(code: "run", level: .casual)],
        achievements: nil, prompts: nil, memberSince: nil, travelCity: nil, badges: nil, cityNo: nil,
        sharedSports: nil, superLikedMe: nil, boosted: nil, note: nil)
}

/// "Like with a note": up to 140 characters; it opens the chat if you match.
struct NoteSheet: View {
    let card: ProfileCard
    let send: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Sp.lg) {
            Text(t("note.title", ["name": card.name])).qText(.title3).accessibilityAddTraits(.isHeader)
            if let c = card.nextChallenge, !c.isEmpty {
                Text(t("note.about", ["challenge": c])).qText(.callout).foregroundStyle(Color.q.inkSoft)
            }
            TextField(t("note.placeholder"), text: $text, axis: .vertical)
                .lineLimit(3...5)
                .padding(.vertical, Sp.md)
                .qField()
                .onChange(of: text) { _, v in if v.count > 140 { text = String(v.prefix(140)) } }
            HStack {
                Text(t("note.hint")).qText(.footnote).foregroundStyle(Color.q.muted)
                Spacer()
                Text("\(text.count)/140").qText(.footnote).monospacedDigit().foregroundStyle(Color.q.muted)
                    .fixedSize()
                    .contentTransition(.numericText())
                    .animation(Motion.snappy, value: text.count)
            }
            Button(t("note.send")) {
                send(text)
                dismiss()
            }
            .buttonStyle(.qPrimary)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(Layout.margin)
        .padding(.top, Sp.sm)
        .frame(maxHeight: .infinity, alignment: .top)
        .qSheet(detents: [.medium])
    }
}

/// The match moment: the two dots meet once, the photos slide together, then the
/// words and the buttons rise in turn. Plays match.wav (from the model).
struct MatchMoment: View {
    let other: ProfileCard
    let myPhoto: String?
    let onWrite: () -> Void
    let onKeep: () -> Void
    @State private var shown = false
    @State private var wordsShown = false
    @State private var buttonsShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.q.blue.ignoresSafeArea()
            Horizon().containerRelativeFrame(.vertical) { h, _ in h * 0.3 }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
            VStack(spacing: Sp.xl) {
                Spacer()
                DotsMeeting(size: 16, color: Color.q.gold, once: true)
                HStack(spacing: -Sp.lg) {
                    Avatar(url: myPhoto.flatMap { URL(string: $0) }, size: 120)
                        .overlay(Circle().stroke(Color.q.gold, lineWidth: 3))
                        .rotationEffect(.degrees(shown ? -6 : 0))
                        .offset(x: shown ? 0 : -60)
                    Avatar(url: other.photoURLs.first, size: 120)
                        .overlay(Circle().stroke(Color.q.gold, lineWidth: 3))
                        .rotationEffect(.degrees(shown ? 6 : 0))
                        .offset(x: shown ? 0 : 60)
                }
                .opacity(shown ? 1 : 0)
                VStack(spacing: Sp.sm) {
                    Text(t("match.title")).qText(.title1).foregroundStyle(.white).accessibilityAddTraits(.isHeader)
                    Text(t("match.sub", ["name": other.name])).qText(.body).foregroundStyle(Color.q.blueMist)
                }
                .multilineTextAlignment(.center)
                .opacity(wordsShown ? 1 : 0)
                .offset(y: wordsShown || reduceMotion ? 0 : 8)
                Spacer()
                VStack(spacing: Sp.md) {
                    Button(t("match.write"), action: onWrite).buttonStyle(.q(.accent))
                    Button(t("match.keep"), action: onKeep).buttonStyle(.qOnBlue)
                }
                .opacity(buttonsShown ? 1 : 0)
                .offset(y: buttonsShown || reduceMotion ? 0 : 12)
            }
            .padding(Layout.margin)
        }
        .onAppear {
            if reduceMotion {
                withAnimation(Motion.fade) { shown = true; wordsShown = true; buttonsShown = true }
                return
            }
            withAnimation(Motion.hero) { shown = true }
            withAnimation(Motion.smooth.delay(0.3)) { wordsShown = true }
            withAnimation(Motion.smooth.delay(0.45)) { buttonsShown = true }
        }
    }
}
