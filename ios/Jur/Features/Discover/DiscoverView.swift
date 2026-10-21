// Discover: tonight's departures on top, then one person at a time.
// Pass / like by button or swipe; long-press like (or the note button) for a like with a note.
import SwiftUI

@MainActor
@Observable
final class DiscoverModel {
    var queue: [ProfileCard] = []
    var tonight: [EventItem] = []
    var loading = false
    var failed = false
    var match: (card: ProfileCard, matchId: UUID)?
    var paywall = false

    var current: ProfileCard? { queue.first }

    func load() async {
        loading = queue.isEmpty
        failed = false
        defer { loading = false }
        do {
            async let people = Backend.discover()
            async let events: [EventItem] = Config.eventsEnabled ? Backend.upcomingEvents() : []
            let (p, e) = try await (people, events)
            queue = p
            tonight = e.filter { Fmt.calendar.isDateInToday($0.start) && $0.end > .now }
        } catch {
            failed = queue.isEmpty
        }
    }

    /// Optimistic: the card leaves at once; on a limit it comes back and the paywall opens.
    func decide(_ kind: SwipeKind, note: String? = nil, toasts: ToastCenter) async {
        guard let card = queue.first else { return }
        queue.removeFirst()
        do {
            let r = try await Backend.swipe(card.id, kind, note: note)
            if !r.ok {
                queue.insert(card, at: 0)
                switch r.error {
                case "like_limit": paywall = true
                case "super_limit": toasts.show(t("discover.superLimit"), error: true)
                default: toasts.show(t("common.error"), error: true)
                }
                return
            }
            if let id = r.matchId { match = (card, id); Haptics.success() }
            if queue.count < 3 { await refill() }
        } catch {
            queue.insert(card, at: 0)
            toasts.show(t("common.error"), error: true)
        }
    }

    func undo(toasts: ToastCenter) async {
        do {
            let r = try await Backend.rewind()
            if let p = r.profile { queue.insert(p, at: 0); return }
            switch r.error {
            case "pro_only": paywall = true
            default: toasts.show(t("undo.nothing"))
            }
        } catch { toasts.show(t("common.error"), error: true) }
    }

    private func refill() async {
        guard let more = try? await Backend.discover() else { return }
        let have = Set(queue.map(\.id))
        queue += more.filter { !have.contains($0.id) }
    }
}

struct DiscoverView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @State private var model = DiscoverModel()
    @State private var noteFor: ProfileCard?
    @State private var drag: CGSize = .zero
    @State private var openEvent: EventItem?
    var openEvents: () -> Void = {}
    var openChat: (UUID) -> Void = { _ in }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Sp.md) {
                    if let p = session.profile {
                        Text(t(greetingKey(), ["name": p.name])).qText(.footnote).foregroundStyle(Color.q.inkSoft)
                    }
                    if !model.tonight.isEmpty {
                        DepartureBoard(departures: model.tonight.prefix(3).map(\.departure),
                                       header: t("board.today", ["city": Cities.label(session.profile?.city ?? "")]),
                                       seeAll: openEvents) { d in
                            openEvent = model.tonight.first { $0.id == d.id }
                        }
                    }
                    deck
                }
                .padding(.horizontal, Layout.margin)
                .padding(.bottom, 120)
            }
            .scrollDisabled(drag != .zero)
            .background(Color.q.bg)
            .refreshable { await model.load() }
            .overlay(alignment: .bottom) { if model.current != nil { actions } }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Lockup(size: 20) }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { LikesView() } label: {
                        Image(systemName: "heart.text.square").accessibilityLabel(t("likes.title"))
                    }
                }
            }
            .navigationDestination(item: $openEvent) { e in EventDetailView(eventId: e.id, initial: e) }
        }
        .task { if model.queue.isEmpty { await model.load() } }
        .sheet(item: $noteFor) { card in
            NoteSheet(card: card) { note in Task { await model.decide(.like, note: note, toasts: toasts) } }
        }
        .sheet(isPresented: $model.paywall) { PaywallView() }
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
        if model.loading {
            ProfileCardView(card: .placeholder, compact: true).redacted(reason: .placeholder)
        } else if model.failed {
            ErrorStateView(retry: { await model.load() }).frame(minHeight: 420)
        } else if let card = model.current {
            ProfileCardView(card: card, compact: true)
                .id(card.id)
                .offset(x: drag.width, y: drag.height * 0.2)
                .rotationEffect(.degrees(Double(drag.width / 24)))
                .overlay(alignment: .top) { swipeHint }
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { drag = $0.translation }
                        .onEnded { v in
                            if v.translation.width > 120 { fling(.like) }
                            else if v.translation.width < -120 { fling(.pass) }
                            else { withAnimation(.spring(duration: 0.3)) { drag = .zero } }
                        }
                )
                .accessibilityAction(named: t("discover.like")) { fling(.like) }
                .accessibilityAction(named: t("discover.pass")) { fling(.pass) }
                .accessibilityAction(named: t("note.add")) { noteFor = card }
                .transition(.asymmetric(insertion: .opacity, removal: .opacity))
        } else {
            QEmptyState(symbol: "figure.run", title: t("discover.empty"),
                        message: t(Config.eventsEnabled ? "discover.emptySub" : "discover.emptySubApp"),
                        actionTitle: Config.eventsEnabled ? t("discover.seeEvents") : nil,
                        action: Config.eventsEnabled ? Optional(openEvents) : nil)
                .frame(minHeight: 420)
        }
    }

    @ViewBuilder private var swipeHint: some View {
        if abs(drag.width) > 40 {
            Text(drag.width > 0 ? t("discover.like") : t("discover.pass"))
                .qText(.title3)
                .foregroundStyle(drag.width > 0 ? Color.q.blue : Color.q.clay)
                .padding(.horizontal, Sp.md).padding(.vertical, Sp.sm)
                .background(Color.q.card, in: Capsule())
                .padding(.top, Sp.xxl)
                .opacity(min(abs(drag.width) / 120, 1))
        }
    }

    private var actions: some View {
        HStack(spacing: Sp.lg) {
            RoundAction(symbol: "arrow.uturn.backward", size: 48, label: t("undo.title")) {
                Task { await model.undo(toasts: toasts) }
            }
            RoundAction(symbol: "xmark", tint: Color.q.clay, size: 64, label: t("discover.pass")) { fling(.pass) }
            RoundAction(symbol: "star.fill", tint: Color.q.onGold, fill: Color.q.gold, size: 48, label: t("discover.super")) {
                Task { await model.decide(.super, toasts: toasts) }
            }
            RoundAction(symbol: "heart.fill", tint: .white, fill: Color.q.blue, size: 64, label: t("discover.like")) { fling(.like) }
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in noteFor = model.current })
        }
        .padding(.bottom, Sp.lg)
    }

    private func fling(_ kind: SwipeKind) {
        withAnimation(.easeIn(duration: 0.18)) { drag = CGSize(width: kind == .like ? 600 : -600, height: 0) }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            drag = .zero
            await model.decide(kind, toasts: toasts)
        }
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

/// The match moment: the two dots meet, then both photos and "Say hi".
struct MatchMoment: View {
    let other: ProfileCard
    let myPhoto: String?
    let onWrite: () -> Void
    let onKeep: () -> Void
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.q.blue.ignoresSafeArea()
            Horizon().containerRelativeFrame(.vertical) { h, _ in h * 0.3 }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
            VStack(spacing: Sp.xl) {
                Spacer()
                DotsMeeting(size: 16, color: Color.q.gold)
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
                VStack(spacing: Sp.sm) {
                    Text(t("match.title")).qText(.title1).foregroundStyle(.white).accessibilityAddTraits(.isHeader)
                    Text(t("match.sub", ["name": other.name])).qText(.body).foregroundStyle(Color.q.blueMist)
                }
                .multilineTextAlignment(.center)
                Spacer()
                VStack(spacing: Sp.md) {
                    Button(t("match.write"), action: onWrite).buttonStyle(.q(.accent))
                    Button(t("match.keep"), action: onKeep).buttonStyle(.qOnBlue)
                }
            }
            .padding(Layout.margin)
            .opacity(shown ? 1 : 0)
        }
        .onAppear {
            if reduceMotion { shown = true } else { withAnimation(.spring(duration: 0.6, bounce: 0.3)) { shown = true } }
        }
    }
}
