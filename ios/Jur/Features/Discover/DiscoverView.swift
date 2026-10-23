// Discover: tonight's departures on top, then one person at a time.
// Pass / like by button or swipe; long-press like (or the note button) for a like with a note.
import SwiftUI
import TipKit

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

    /// When the top card appeared, and passes so far this session (for the undo toast).
    private var shownAt = Date.now
    private var passes = 0
    /// Swipes still on their way to the server; undo waits for them so it never races one.
    @ObservationIgnored private var sending: [UUID: Task<Void, Never>] = [:]

    /// Optimistic: the card leaves at once (animated); on a limit it comes back and the paywall opens.
    func commit(_ kind: SwipeKind, note: String? = nil, toasts: ToastCenter) {
        guard let card = queue.first else { return }
        let quick = Date.now.timeIntervalSince(shownAt) < 2
        withMotion(Motion.smooth) { _ = queue.removeFirst() }
        shownAt = .now
        prefetchNext()
        SwipeTip().invalidate(reason: .actionPerformed)
        if kind == .like { Task { await NoteTip.liked.donate() } }
        if note != nil { NoteTip().invalidate(reason: .actionPerformed) }
        // "Пропущено · Вернуть": when the pass was quick (likely by accident) or while
        // someone is still learning the deck. Not after every pass: that would nag.
        if kind == .pass {
            passes += 1
            if quick || passes <= 3 {
                // The toast names this person, so it brings back this person (not whoever was passed last).
                toasts.show(t("discover.passed", ["name": card.name]), symbol: "arrow.uturn.backward",
                            action: t("discover.undo")) { [weak self] in
                    Task { await self?.undo(card.id, toasts: toasts) }
                }
            }
        }
        sending[card.id] = Task { [weak self] in
            await self?.send(card, kind, note: note, toasts: toasts)
            self?.sending[card.id] = nil
        }
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
            toasts.show(error)
        }
    }

    /// Puts a card back on top, coming in from the side it left.
    private func restore(_ card: ProfileCard, after kind: SwipeKind) {
        returningId = card.id
        returningEdge = kind == .pass ? .leading : kind == .super ? .top : .trailing
        withMotion(Motion.bouncy) { queue.insert(card, at: 0) }
    }

    /// `target`: the person the toast named. Without one (the Undo button): the last swipe.
    func undo(_ target: UUID? = nil, toasts: ToastCenter) async {
        if let target { await sending[target]?.value } else { for task in sending.values { await task.value } }
        do {
            let r = try await Backend.rewind(target)
            if let p = r.profile {
                queue.removeAll { $0.id == p.id }
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
        } catch { toasts.show(error) }
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
                    if session.profile?.paused == true {
                        PausedBanner { await model.reload() }
                    }
                    if !model.tonight.isEmpty {
                        DepartureBoard(departures: model.tonight.prefix(3).map(\.departure),
                                       header: t("board.today", ["city": Cities.label(session.profile?.effectiveCity ?? "")]),
                                       seeAll: openEvents) { d in
                            openEvent = model.tonight.first { $0.id == d.id }
                        }
                        .qScrollDepth()
                    }
                    deck
                }
                .padding(.horizontal, Layout.margin)
                .padding(.bottom, Layout.floatingBarClearance)
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
        // Filters or city changed somewhere else (Settings): start the deck over.
        .onChange(of: session.profile.map { DeckKey($0) }) { old, new in
            if old != nil, old != new { Task { await model.reload() } }
        }
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
            // Saving refreshes the profile; the onChange below starts the deck over.
            FiltersSheet {}
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
            TipView(SwipeTip(), arrowEdge: .bottom)
                .tipBackground(Color.q.card)
                .padding(.bottom, Sp.xs)
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
                .popoverTip(NoteTip(), arrowEdge: .bottom)
            BoostButton(round: true) { boostPaywall = true }
        }
        .opacity(dealt ? 1 : 0)
        .scaleEffect(dealt || Motion.reduceMotion ? 1 : 0.8)
        .animation(Motion.adaptive(Motion.bouncy).delay(0.45), value: dealt)
        .padding(.bottom, Sp.lg)
    }

}

/// What the deck depends on: change any of it and the deck starts over.
private struct DeckKey: Equatable {
    let filters: DiscoverFilters
    let city: String
    init(_ p: MyProfile) { filters = DiscoverFilters(p); city = p.effectiveCity }
}

/// On pause nobody sees you in Discover, and likes you send wait until you're back.
/// Said where it matters, with the way back right there.
struct PausedBanner: View {
    let onResumed: () async -> Void
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @State private var busy = false

    var body: some View {
        HStack(alignment: .top, spacing: Sp.md) {
            Image(systemName: "pause.circle.fill").font(.q(.title3)).foregroundStyle(Color.q.clay)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Sp.xxs) {
                Text(t("discover.pausedTitle")).qText(.callout).foregroundStyle(Color.q.ink)
                Text(t("discover.pausedBody")).qText(.footnote).foregroundStyle(Color.q.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Sp.sm)
            Button { Task { await resume() } } label: { BusyLabel(title: t("discover.resume"), busy: busy) }
                .buttonStyle(.q(.secondary, compact: true))
                .fixedSize()
                .disabled(busy)
        }
        .padding(Sp.lg)
        .background(Color.q.card, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
        .transition(.opacity)
    }

    private func resume() async {
        busy = true
        defer { busy = false }
        do {
            try await Backend.setPaused(false)
            await session.refreshProfile()
            Haptics.tick()
            toasts.show(t("me2.resumed"), symbol: "eye.fill")
            await onResumed()
        } catch { toasts.show(error) }
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
    @FocusState private var typing: Bool
    private var draftId: String { "note.\(card.id.uuidString.lowercased())" }

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
                .focused($typing)
                .limited($text, to: 140)
                // Closed by accident? The note is still there next time.
                .onChange(of: text) { _, v in Drafts.set(draftId, v) }
            HStack {
                Text(t("note.hint")).qText(.footnote).foregroundStyle(Color.q.muted)
                Spacer()
                Text("\(text.count)/140").qText(.footnote).monospacedDigit().foregroundStyle(Color.q.muted)
                    .fixedSize()
                    .contentTransition(.numericText())
                    .animation(Motion.snappy, value: text.count)
            }
            Button(t("note.send")) {
                Drafts.set(draftId, "")
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
        .onAppear {
            text = Drafts.get(draftId)
            // Opened to write: the keyboard comes up with it.
            typing = true
        }
    }
}

/// The match moment, JÜR's biggest: the two dots meet once, the photos slide together,
/// then the match seal slams down where they overlap (they give under it, gold dust
/// flies, a thump), and the words and buttons rise in turn. Plays match.wav (from the model).
struct MatchMoment: View {
    let other: ProfileCard
    let myPhoto: String?
    let onWrite: () -> Void
    let onKeep: () -> Void
    @State private var shown = false
    @State private var sealed = false
    @State private var dip = false
    @State private var burst = 0
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
                .stampDip(dip)
                .overlay(alignment: .bottom) {
                    ZStack {
                        DustBurst(trigger: burst)
                        MatchSeal().stampSlam(sealed)
                    }
                    .offset(y: 36)
                }
                .opacity(shown ? 1 : 0)
                .padding(.bottom, Sp.xl)
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
        .task {
            withAnimation(Motion.adaptive(Motion.hero)) { shown = true }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 650))
            // The success haptic and the sound already played when the match came back.
            await StampMoment.play(land: { sealed = true }, dip: { dip = $0 }, dust: { burst += 1 }, success: false)
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(Motion.adaptive(Motion.smooth)) { wordsShown = true }
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(Motion.adaptive(Motion.smooth)) { buttonsShown = true }
        }
    }
}

/// The seal on a match: the mark in gold inside a double gold ring, on blue.
struct MatchSeal: View {
    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = 84

    var body: some View {
        ZStack {
            Circle().fill(Color.q.blueDeep)
            Circle().strokeBorder(Color.q.gold, lineWidth: 3)
            Circle().strokeBorder(Color.q.gold.opacity(0.7), lineWidth: 1).padding(6)
            VStack(spacing: 0) {
                MarkView(size: size * 0.36, color: Color.q.gold)
                Text(t("match.seal").uppercased())
                    .font(.q(.label))
                    .tracking(1.5)
                    .foregroundStyle(Color.q.gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, Sp.md)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-10))
        .shadow(color: Color.q.boardShade.opacity(0.5), radius: 8, y: 4)
        .accessibilityHidden(true)
    }
}
