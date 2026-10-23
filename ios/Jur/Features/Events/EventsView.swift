// Events as a departure board: Today / Tomorrow / Weekend. Verified members can
// create one (free, up to 50 people, 3 upcoming at a time).
import SwiftUI

struct EventsView: View {
    enum Window: String, CaseIterable, Identifiable { case today, tomorrow, weekend; var id: Self { self } }

    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(SportsCatalog.self) private var catalog
    /// Last time's list, so the board draws at once and refreshes behind.
    @State private var events: [EventItem] = EventsView.saved ?? []
    @State private var loaded = EventsView.saved != nil
    @State private var failed = false
    /// The placeholder board appears only if the answer takes longer than a blink.
    @State private var slow = false
    @State private var range: Window = .today
    @State private var creating = false
    @Binding var path: [UUID]

    private var canHost: Bool {
        guard let p = session.profile else { return false }
        return p.isHost || p.verificationStatus == .approved
    }

    private var shown: [EventItem] {
        let cal = Fmt.calendar
        return events.filter { e in
            switch range {
            case .today: return cal.isDateInToday(e.start) && e.end > .now
            case .tomorrow: return cal.isDateInTomorrow(e.start)
            case .weekend:
                guard let weekend = cal.nextWeekend(startingAfter: cal.startOfDay(for: .now).addingTimeInterval(-1)) else { return false }
                return e.start >= weekend.start && e.start < weekend.end
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: Sp.lg) {
                    Picker("", selection: $range) {
                        Text(t("board.segToday")).tag(Window.today)
                        Text(t("board.segTomorrow")).tag(Window.tomorrow)
                        Text(t("board.segWeekend")).tag(Window.weekend)
                    }
                    .pickerStyle(.segmented)
                    .sensoryFeedback(.selection, trigger: range)

                    // One slot for whatever shows under the switch. While one view fades out and
                    // the next fades in they overlap here instead of stacking, so the page
                    // never grows for a moment and snaps back.
                    ZStack(alignment: .top) {
                    if failed && events.isEmpty {
                        ErrorStateView(retry: { await load() }).frame(minHeight: 300)
                    } else if !loaded {
                        if slow {
                            // One row, the size an answer most often is: nothing collapses after.
                            DepartureBoard(departures: [Departure(id: UUID(), time: "19:00", title: "Падел · парная игра",
                                                                  place: "Padel Club", status: .onTime)])
                                .redacted(reason: .placeholder)
                                .qShimmer()
                                .transition(.opacity)
                        }
                    } else if !shown.isEmpty {
                        DepartureBoard(departures: shown.map(\.departure), showsColumns: true, onSelect: { d in path.append(d.id) })
                            .transition(.opacity)
                    } else if let next = nextUp {
                        dayEmpty(next)
                    } else {
                        allQuiet
                    }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Layout.margin)
                .padding(.bottom, Sp.xl)
            }
            .animation(Motion.adaptive(Motion.smooth), value: range)
            .animation(Motion.adaptive(Motion.fade), value: loaded)
            .animation(Motion.adaptive(Motion.fade), value: slow)
            .background(Color.q.bg)
            .navigationTitle(t("tabs.events"))
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { create() } label: {
                        Image(systemName: "plus").accessibilityLabel(t("events.create"))
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                EventDetailView(eventId: id, initial: events.first { $0.id == id }) { Task { await load() } }
            }
            .refreshable { await load() }
            .task {
                // Coming back to the tab: the list on screen is fresh enough for a minute.
                if loaded, let last = Self.lastLoad, Date.now.timeIntervalSince(last) < 60 { return }
                let waiting = Task { try? await Task.sleep(for: .milliseconds(350)); if !Task.isCancelled { slow = true } }
                await load()
                waiting.cancel()
            }
            .sheet(isPresented: $creating) {
                NewEventView { id in
                    Task { await load(); path.append(id) }
                }
            }
        }
    }

    /// When the chosen day is empty: the nearest day that has events, and its events.
    private var nextUp: (day: Date, events: [EventItem])? {
        guard shown.isEmpty else { return nil }
        let cal = Fmt.calendar
        let ahead = events.filter { $0.end > .now }.sorted { $0.start < $1.start }
        guard let first = ahead.first else { return nil }
        let day = cal.startOfDay(for: first.start)
        return (day, ahead.filter { cal.isDate($0.start, inSameDayAs: day) })
    }

    /// The tab that contains `day`, if any (events further out have no tab).
    private func window(for day: Date) -> Window? {
        let cal = Fmt.calendar
        if cal.isDateInToday(day) { return .today }
        if cal.isDateInTomorrow(day) { return .tomorrow }
        if let weekend = cal.nextWeekend(startingAfter: cal.startOfDay(for: .now).addingTimeInterval(-1)),
           day >= weekend.start && day < weekend.end { return .weekend }
        return nil
    }

    private func dayLabel(_ day: Date) -> String {
        let cal = Fmt.calendar
        if cal.isDateInToday(day) { return t("empty.today") }
        if cal.isDateInTomorrow(day) { return t("empty.tomorrow") }
        return Fmt.day(day)
    }

    /// The chosen day is empty but others aren't: one line saying so, then the nearest day's
    /// board right under it, then a quiet way to start your own. No gaps, no lone empty board.
    private func dayEmpty(_ next: (day: Date, events: [EventItem])) -> some View {
        let target = window(for: next.day)
        let first = next.events[0]
        return VStack(alignment: .leading, spacing: Sp.md) {
            HStack(spacing: Sp.md) {
                MarkView(size: 24, color: Color.q.blueText)
                    .frame(width: 40, height: 40)
                    .background(Color.q.blueTint, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                VStack(alignment: .leading, spacing: Sp.xxs) {
                    Text(t("events2.empty\(range.rawValue.capitalized)")).qText(.headline).foregroundStyle(Color.q.ink)
                    Text(t("events2.nearest", ["when": dayLabel(next.day) + " · " + Fmt.time(first.start)]))
                        .qText(.footnote).foregroundStyle(Color.q.muted)
                }
                Spacer(minLength: 0)
            }
            .qCard(padding: Sp.md)
            .accessibilityElement(children: .combine)

            DepartureBoard(departures: next.events.prefix(3).map(\.departure),
                           header: t("empty.nextTitle", ["day": dayLabel(next.day)]),
                           seeAll: target.map { w in { range = w } }, onSelect: { d in path.append(d.id) })

            HStack(spacing: Sp.md) {
                Text(t("events2.makeYourOwn")).qText(.callout).foregroundStyle(Color.q.inkSoft)
                Spacer(minLength: Sp.sm)
                Button(t("events2.create")) { create() }
                    .buttonStyle(.q(.secondary, compact: true))
                    .fixedSize()
            }
            .padding(.horizontal, Sp.xs)
        }
        .transition(.opacity)
    }

    /// Nothing anywhere: one calm empty state in the middle of the free space.
    private var allQuiet: some View {
        VStack(spacing: Sp.md) {
            VStack(spacing: Sp.xs) {
                Text(verbatim: "—:—").qText(.display).foregroundStyle(Color.q.gold)
                Text(t("events2.noDepartures")).qText(.label).foregroundStyle(Color.q.blueMist)
                    .padding(.bottom, Sp.md)
                ZStack {
                    RidgeShape(layer: .far).fill(Color.q.boardRidge)
                    SnowCaps().fill(.white.opacity(0.92))
                    RidgeShape(layer: .near).fill(Color.q.boardShade.opacity(0.6))
                }
                .frame(height: 44)
            }
            .padding(.top, Sp.lg)
            .frame(width: 220)
            .background(Color.q.boardGround)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .accessibilityHidden(true)

            Text(t("events2.quietTitle", ["city": Cities.label(session.profile?.city ?? "")]))
                .qText(.title3).foregroundStyle(Color.q.ink).multilineTextAlignment(.center)
                .padding(.top, Sp.xs)
            Text(t("events2.quietBody")).qText(.callout).foregroundStyle(Color.q.inkSoft)
                .multilineTextAlignment(.center).frame(maxWidth: 300)
            Button(t("board.create")) { create() }
                .buttonStyle(.qPrimary)
                .frame(maxWidth: 300)
                .padding(.top, Sp.xs)
        }
        .frame(maxWidth: .infinity)
        // Centred in the space under the day switch, clear of the tab bar.
        .containerRelativeFrame(.vertical) { height, _ in height * 0.72 }
        .transition(.opacity)
    }

    private func create() {
        if canHost { creating = true } else { toasts.show(t("events.verifyToHost")) }
    }

    private static var saved: [EventItem]? {
        DataCache.get(CacheKey.events, as: [EventItem].self)?.sorted { $0.start < $1.start }
    }

    /// When the list last came from the server (shared across visits to the tab).
    @MainActor private static var lastLoad: Date?

    private func load() async {
        failed = false
        do {
            let fresh = try await Backend.upcomingEvents()
            Self.lastLoad = .now
            // Same as on screen (usually, after the saved copy): nothing to redraw.
            // Different: swap without row animations, so nothing slides or collapses.
            if fresh != events {
                var quiet = Transaction()
                quiet.disablesAnimations = true
                withTransaction(quiet) { events = fresh }
            }
        } catch { failed = true }
        loaded = true
        slow = false
        LiveDepartures.sync(events) { catalog.sport($0)?.emoji ?? "" }
    }
}

/// One event: when, where, who's going; join / leave; boarding (check-in) at the time;
/// the host sees the live 4-digit code.
struct EventDetailView: View {
    let eventId: UUID
    var initial: EventItem?
    var onChange: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(SportsCatalog.self) private var catalog
    @State private var event: EventItem?
    @State private var busy = false
    @State private var boarding = false
    @State private var code = ""
    @State private var codeError = false
    @State private var hostCode: String?
    @State private var reloadTick = 0
    /// The "showed up" stamp landing after a successful check-in.
    @State private var stamp: StampData?
    /// Who's going: nil until loaded (and while you're not going).
    @State private var people: [ProfileCard]?
    @State private var confirmLeave = false
    @Environment(\.openURL) private var openURL

    private var isHost: Bool { event?.hostId != nil && event?.hostId == session.userId }

    var body: some View {
        ScrollView {
            if let e = event {
                VStack(alignment: .leading, spacing: Sp.md) {
                    hero(e)
                    facts(e)
                    if isHost { hostCard(e) }
                    people(e)
                    about(e)
                }
                .padding(.horizontal, Layout.margin)
                .padding(.bottom, Sp.lg)
            } else {
                AfterABlink { MarkLoader().padding(.top, Sp.xxl) }
            }
        }
        .background(Color.q.bg)
        // The one action, always in reach: join, going, boarding, or why not.
        .safeAreaInset(edge: .bottom) { if let e = event { bottomBar(e) } }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let e = event, !e.cancelled, e.end > .now {
                ToolbarItem(placement: .topBarTrailing) {
                    SharePassButton(pass: .event(e, sport: catalog.label(e.sportCode)),
                                    text: t("pass.eventShareText", ["title": e.title, "when": Fmt.dayTime(e.start),
                                                                    "url": Config.appStoreURL.absoluteString])) {
                        Image(systemName: "square.and.arrow.up").accessibilityLabel(t("pass.share"))
                    }
                }
            }
        }
        .overlay {
            if let stamp {
                StampLanding(data: stamp, city: event.map { Cities.label($0.city) }) {
                    withMotion(Motion.fade) { self.stamp = nil }
                }
                .transition(.opacity)
            }
        }
        .task { if event == nil { event = initial }; await load() }
        .task(id: event?.iAmGoing) { await loadPeople() }
        .sheet(isPresented: $boarding) {
            BoardingCodeSheet(eventTitle: event.map { "\($0.title) \(Fmt.time($0.start))" } ?? "",
                              code: $code, busy: busy, isError: codeError) {
                Task { await checkIn() }
            }
        }
        .confirmationDialog(t("eventd.leaveTitle"), isPresented: $confirmLeave, titleVisibility: .visible) {
            Button(t("events.leave"), role: .destructive) { Task { await leave() } }
            Button(t("common.cancel"), role: .cancel) {}
        }
    }

    // MARK: parts

    /// Night-blue, like the departure board: sport, title, the time large, and how soon.
    private func hero(_ e: EventItem) -> some View {
        VStack(alignment: .leading, spacing: Sp.sm) {
            HStack(spacing: Sp.sm) {
                Text(catalog.label(e.sportCode)).qText(.overline).foregroundStyle(Color.q.blueMist)
                Spacer(minLength: 0)
                if e.cancelled {
                    QTag(label: t("eventd.cancelled"), tone: .clay)
                } else if e.boardingOpen && e.end > .now {
                    QTag(label: t("eventd.boarding"), tone: .gold)
                }
            }
            Text(e.title).qText(.title1).foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .firstTextBaseline, spacing: Sp.sm) {
                Text(Fmt.time(e.start)).font(.q(.display)).foregroundStyle(Color.q.gold)
                Text(whenText(e)).qText(.callout).foregroundStyle(Color.q.blueMist)
            }
        }
        .padding(Sp.lg)
        .padding(.bottom, Sp.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                Color.q.boardGround
                Horizon(far: Color.q.boardRidge, near: Color.q.boardShade, snow: false).frame(height: 44)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// "сегодня · через 2 ч", "завтра · через 11 ч", "сб 25 окт".
    private func whenText(_ e: EventItem) -> String {
        let cal = Fmt.calendar
        let day = cal.isDateInToday(e.start) ? t("empty.today") : cal.isDateInTomorrow(e.start) ? t("empty.tomorrow") : Fmt.day(e.start)
        guard e.start > .now, e.start.timeIntervalSinceNow < 48 * 3600 else { return day }
        let f = RelativeDateTimeFormatter()
        f.locale = L10n.current.locale
        f.unitsStyle = .short
        return day + " · " + f.localizedString(for: e.start, relativeTo: .now)
    }

    /// Where (opens a route) and how many spots.
    private func facts(_ e: EventItem) -> some View {
        HStack(alignment: .top, spacing: Sp.sm) {
            Button { openRoute(e) } label: {
                VStack(alignment: .leading, spacing: Sp.xxs) {
                    Text(t("eventd.where")).qText(.label).foregroundStyle(Color.q.muted)
                    Text(e.meetingPoint).qText(.headline).foregroundStyle(Color.q.ink)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Text(t("eventd.route")).qText(.footnote).fontWeight(.bold).foregroundStyle(Color.q.blueText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .qCard(padding: Sp.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.qPressCard)
            VStack(alignment: .leading, spacing: Sp.xxs) {
                Text(t("eventd.spots")).qText(.label).foregroundStyle(Color.q.muted)
                Text(verbatim: "\(e.goingCount) / \(e.capacity)").qText(.number).foregroundStyle(Color.q.ink)
                    .contentTransition(.numericText())
                Text(t("events.durationMin", ["n": e.durationMin])).qText(.footnote).foregroundStyle(Color.q.muted)
            }
            .frame(width: 112, alignment: .leading)
            .qCard(padding: Sp.md)
            .accessibilityElement(children: .combine)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 2GIS (the map everyone here uses) by search; the web page opens the app when it's installed.
    private func openRoute(_ e: EventItem) {
        let q = "\(e.meetingPoint), \(Cities.label(e.city))"
        if let enc = q.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let url = URL(string: "https://2gis.kz/search/\(enc)") {
            openURL(url)
        }
    }

    /// Who's going: faces once you're going (that's when the list opens), a promise before.
    private func people(_ e: EventItem) -> some View {
        VStack(alignment: .leading, spacing: Sp.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(t("eventd.who")).qText(.label).foregroundStyle(Color.q.muted)
                Spacer()
                if e.iAmGoing, let people, !people.isEmpty {
                    NavigationLink { EventPeopleView(title: e.title, people: people) } label: {
                        Text(t("eventd.all", ["n": people.count])).qText(.footnote).fontWeight(.bold)
                            .foregroundStyle(Color.q.blueText)
                    }
                }
            }
            if e.iAmGoing, let people {
                if people.isEmpty {
                    Text(t("eventd.nobody")).qText(.callout).foregroundStyle(Color.q.inkSoft)
                } else {
                    FacePile(people: Array(people.prefix(5)), extra: max(people.count - 5, 0))
                    let open = people.filter { $0.openToMeet == true }.count
                    let mine = people.filter { matchIds.contains($0.id) }.count
                    let line = [open > 0 ? t("eventd.open", ["n": open]) : nil,
                                mine > 0 ? t("eventd.matches", ["n": mine]) : nil].compactMap { $0 }
                    if !line.isEmpty {
                        HStack(spacing: Sp.xs) {
                            Circle().fill(Color.q.gold).frame(width: Sp.sm + Sp.xxs, height: Sp.sm + Sp.xxs).accessibilityHidden(true)
                            Text(line.joined(separator: " · ")).qText(.footnote).foregroundStyle(Color.q.muted)
                        }
                    }
                }
            } else if e.goingCount > 0 {
                HStack(spacing: Sp.md) {
                    FacePile(people: [], extra: 0, placeholders: min(e.goingCount, 4))
                    Text(t("eventd.locked")).qText(.footnote).foregroundStyle(Color.q.muted)
                }
            } else {
                Text(t("eventd.nobody")).qText(.callout).foregroundStyle(Color.q.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .qCard()
    }

    @ViewBuilder private func about(_ e: EventItem) -> some View {
        VStack(alignment: .leading, spacing: Sp.sm) {
            if let d = e.description, !d.isEmpty {
                Text(d).qText(.body).foregroundStyle(Color.q.ink)
            }
            if let h = e.host {
                HStack(spacing: Sp.sm) {
                    Avatar(url: h.photo.flatMap(URL.init(string:)), size: 24)
                    Text(t("eventd.hostedBy", ["name": h.name])).qText(.footnote).foregroundStyle(Color.q.muted)
                }
            }
        }
        .padding(.horizontal, Sp.xs)
        .padding(.top, Sp.xs)
    }

    /// Price and spots on the left; the one thing to do on the right.
    private func bottomBar(_ e: EventItem) -> some View {
        HStack(spacing: Sp.md) {
            VStack(alignment: .leading, spacing: Sp.xxs) {
                Text(e.priceKzt == 0 ? t("eventd.free") : "\(e.priceKzt) ₸").qText(.headline).foregroundStyle(Color.q.ink)
                Text(t("eventd.spotsLeft", ["n": e.spotsLeft])).qText(.footnote).foregroundStyle(Color.q.muted)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: Sp.sm)
            barAction(e)
        }
        .padding(.horizontal, Layout.margin)
        .padding(.top, Sp.md)
        .padding(.bottom, Sp.sm)
        .background(.bar)
        .overlay(alignment: .top) { Rectangle().fill(Color.q.line).frame(height: 1) }
    }

    @ViewBuilder private func barAction(_ e: EventItem) -> some View {
        if e.cancelled || e.end < .now {
            QTag(label: t(e.cancelled ? "eventd.cancelled" : "eventd.over"), tone: .neutral)
        } else if isHost {
            QTag(label: t("eventd.hosting"), tone: .blue, systemImage: "flag.fill")
        } else if e.iCheckedIn {
            QTag(label: t("events.checkedIn"), tone: .good, systemImage: "checkmark").transition(.qPop)
        } else if e.iAmGoing && e.boardingOpen {
            Button(t("eventd.boarding")) { code = ""; codeError = false; boarding = true }
                .buttonStyle(.q(.primary, compact: true)).fixedSize()
        } else if e.iAmGoing {
            Button { confirmLeave = true } label: { Label(t("eventd.going"), systemImage: "checkmark") }
                .buttonStyle(.q(.secondary, compact: true)).fixedSize().disabled(busy)
        } else if e.isFull {
            QTag(label: t("events.full"), tone: .neutral).transition(.qPop)
        } else {
            Button { Task { await join() } } label: { BusyLabel(title: t("eventd.join"), busy: busy) }
                .buttonStyle(.q(.primary, compact: true)).fixedSize().disabled(busy)
        }
    }

    /// The host's boarding code, refreshed every minute.
    private func hostCard(_ e: EventItem) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = 60 - Calendar.current.component(.second, from: context.date)
            VStack(alignment: .leading, spacing: Sp.sm) {
                Text(t("board.hostCodeTitle")).qText(.overline).foregroundStyle(Color.q.clayDeep)
                Text(hostCode ?? "····").font(.q(.display)).tracking(8).foregroundStyle(Color.q.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(Motion.adaptive(Motion.smooth), value: hostCode)
                    .accessibilityLabel(hostCode.map { $0.map(String.init).joined(separator: " ") } ?? "")
                Text(t("board.hostCodeHint", ["s": left])).qText(.footnote).foregroundStyle(Color.q.muted)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(Motion.adaptive(Motion.snappy), value: left)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .qCard()
            .onChange(of: left == 60) { _, minuteTurned in if minuteTurned { reloadTick += 1 } }
        }
        .task(id: reloadTick) { hostCode = (try? await Backend.hostCode(e.id))?.code }
    }

    /// People you're matched with (from the matches list on the phone).
    private var matchIds: Set<UUID> {
        Set((DataCache.get(CacheKey.matches, as: [MatchRow].self) ?? []).map(\.other.id))
    }

    private func loadPeople() async {
        guard let e = event, e.iAmGoing else { people = nil; return }
        if let p = try? await Backend.eventPeople(e.id) { withMotion(Motion.fade) { people = p } }
    }

    private func load() async {
        guard let fresh = try? await Backend.event(eventId) else { return }
        if event == nil { event = fresh } else { withMotion(Motion.smooth) { event = fresh } }
    }

    /// Instant: "going" and the count change before the server answers, and change back
    /// with a reason if it says no (full, cancelled).
    private func join() async {
        guard let e = event else { return }
        busy = true
        defer { busy = false }
        withMotion(Motion.snappy) { event?.iAmGoing = true; event?.goingCount += 1 }
        Haptics.success()
        do {
            let r = try await Backend.joinEvent(e.id)
            if r.ok { toasts.show(t("events.youreIn")) }
            else {
                withMotion(Motion.snappy) { event = e }
                toasts.show(t(r.error == "full" ? "events.full" : "err.generic"), error: true)
            }
            await load()
            onChange()
        } catch {
            withMotion(Motion.snappy) { event = e }
            toasts.show(error)
        }
    }

    private func leave() async {
        guard let e = event else { return }
        busy = true
        defer { busy = false }
        withMotion(Motion.snappy) { event?.iAmGoing = false; event?.goingCount = max(e.goingCount - 1, 0) }
        Haptics.tick()
        do {
            try await Backend.leaveEvent(e.id)
            await load()
            onChange()
        } catch {
            withMotion(Motion.snappy) { event = e }
            toasts.show(error)
        }
    }

    private func checkIn() async {
        guard let e = event else { return }
        busy = true
        codeError = false
        defer { busy = false }
        do {
            let r = try await Backend.checkIn(e.id, code: code)
            if r.ok {
                boarding = false
                withMotion(Motion.fade) { stamp = StampData(kind: .showed_up, detail: Fmt.time(e.start)) }
                await load()
                onChange()
            } else {
                codeError = true
                Haptics.failure()
                switch r.error {
                case "not_now": toasts.show(t("events.notNow"), error: true)
                case "too_many_tries":
                    let at = r.retryAt.flatMap { Date.iso($0) }.map(Fmt.time) ?? ""
                    toasts.show(t("board.tooManyTries", ["time": at]), error: true)
                default: toasts.show(t("board.badCode"), error: true)
                }
            }
        } catch { toasts.show(error) }
    }
}

/// A member's event: free, up to 50 people, within the next 60 days.
struct NewEventView: View {
    let onCreated: (UUID) -> Void
    @Environment(SessionStore.self) private var session
    @Environment(SportsCatalog.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var sport = ""
    @State private var start = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var duration = 90
    @State private var capacity = 8
    @State private var place = ""
    @State private var about = ""
    @State private var busy = false
    @State private var error: String?
    @State private var confirmCancel = false
    @FocusState private var focus: Field?

    private enum Field { case title, place, about }

    /// Anything typed or chosen: closing the sheet asks first.
    private var dirty: Bool { !title.isEmpty || !place.isEmpty || !about.isEmpty || !sport.isEmpty }

    private var valid: Bool {
        title.trimmingCharacters(in: .whitespaces).count >= 3 && !sport.isEmpty
            && place.trimmingCharacters(in: .whitespaces).count >= 3 && start > .now
    }

    var body: some View {
        NavigationStack {
            QForm {
                Section {
                    VStack(alignment: .trailing, spacing: Sp.xxs) {
                        TextField(t("events.fieldTitle"), text: $title)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.next)
                            .focused($focus, equals: .title)
                            .limited($title, to: 80)
                            .onSubmit { focus = .place }
                        CharCounter(count: title.count, limit: 80)
                    }
                    Picker(t("events.fieldSport"), selection: $sport) {
                        Text("—").tag("")
                        ForEach(catalog.all) { s in Text("\(s.emoji) \(s.name)").tag(s.code) }
                    }
                }
                Section {
                    DatePicker(t("date.when"), selection: $start,
                               in: Date.now...(Calendar.current.date(byAdding: .day, value: 60, to: .now) ?? .now))
                        .environment(\.timeZone, Fmt.zone)
                    Stepper(t("events.durationMin", ["n": duration]), value: $duration, in: 30...360, step: 15)
                    Stepper(t("events.capacityN", ["n": capacity]), value: $capacity, in: 2...50)
                }
                Section {
                    VStack(alignment: .trailing, spacing: Sp.xxs) {
                        // Places and club names: no autocorrect turning "Padel Club" into something else.
                        TextField(t("events.fieldMeeting"), text: $place)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focus, equals: .place)
                            .limited($place, to: 160)
                            .onSubmit { focus = .about }
                        CharCounter(count: place.count, limit: 160)
                    }
                    VStack(alignment: .trailing, spacing: Sp.xxs) {
                        TextField(t("events.fieldDescription"), text: $about, axis: .vertical)
                            .lineLimit(3...8)
                            .focused($focus, equals: .about)
                            .limited($about, to: 1500)
                        CharCounter(count: about.count, limit: 1500)
                    }
                } footer: {
                    Text(t("events.memberRules")).qText(.footnote)
                }
                if let error { Section { Text(error).foregroundStyle(Color.q.danger) } }
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Color.q.bg)
            .navigationTitle(t("events.create"))
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(dirty)
            .confirmationDialog(t("events.discardTitle"), isPresented: $confirmCancel, titleVisibility: .visible) {
                Button(t("edit.discard"), role: .destructive) { dismiss() }
                Button(t("events.keepEditing"), role: .cancel) {}
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.cancel")) { if dirty { confirmCancel = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("events.publish")) { Task { await publish() } }.disabled(!valid || busy)
                }
            }
            .task { await catalog.load() }
        }
        .qSheet(detents: [.large])
    }

    private func publish() async {
        guard let p = session.profile else { return }
        busy = true
        error = nil
        defer { busy = false }
        let e = Backend.NewEvent(
            hostId: p.id, city: p.city, sportCode: sport, title: title.trimmingCharacters(in: .whitespaces),
            description: about.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            meetingPoint: place.trimmingCharacters(in: .whitespaces),
            startsAt: ISO8601DateFormatter().string(from: start), durationMin: duration, capacity: capacity, priceKzt: 0)
        do {
            let id = try await Backend.createEvent(e)
            dismiss()
            onCreated(id)
        } catch {
            let s = "\(error)"
            self.error = s.contains("too_many_upcoming") ? t("events.tooMany") : t("events.invalid")
        }
    }
}

/// Check-in's moment, the same as the passport being issued: the felt card rises, the
/// "showed up" stamp slams down big and turned, the card dips, gold dust flies, a thump.
/// Then it clears itself (or on tap).
struct StampLanding: View {
    let data: StampData
    var city: String?
    let onDone: () -> Void
    @State private var cardIn = false
    @State private var landed = false
    @State private var dip = false
    @State private var burst = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.q.overlay.ignoresSafeArea()
            VStack(spacing: Sp.lg) {
                ZStack {
                    DustBurst(trigger: burst)
                    Stamp(data: data, city: city).stampSlam(landed)
                }
                Text(t("events.checkedIn")).qText(.headline).foregroundStyle(Color.q.feltInk)
            }
            .padding(Sp.xxl)
            .background(Color.q.feltGround, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .qElevated()
            .rotationEffect(.degrees(cardIn || reduceMotion ? -2 : -7))
            .offset(y: cardIn || reduceMotion ? 0 : 60)
            .opacity(cardIn ? 1 : 0)
            .stampDip(dip)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDone)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isModal)
        .task {
            withAnimation(Motion.adaptive(Motion.hero)) { cardIn = true }
            try? await Task.sleep(for: .milliseconds(350))
            await StampMoment.play(land: { landed = true }, dip: { dip = $0 }, dust: { burst += 1 })
            Sounds.play(.checkin)
            try? await Task.sleep(for: .seconds(2))
            onDone()
        }
    }
}

/// Overlapping faces; a gold ring marks someone open to meeting. With no people, plain
/// circles stand in (the list opens once you're going).
struct FacePile: View {
    let people: [ProfileCard]
    let extra: Int
    var placeholders = 0
    private let size: CGFloat = 48
    /// The ring around each face (gold when open to meeting, the card colour otherwise).
    private let ring: CGFloat = Sp.xxs + 1

    var body: some View {
        HStack(spacing: -Sp.md) {
            ForEach(people) { p in
                Avatar(url: p.photoURLs.first, size: size - ring * 2)
                    .padding(ring)
                    .background(p.openToMeet == true ? Color.q.gold : Color.q.card, in: Circle())
            }
            ForEach(0..<placeholders, id: \.self) { _ in
                Circle().fill(Color.q.blueTint).frame(width: size - ring * 2, height: size - ring * 2)
                    .padding(ring).background(Color.q.card, in: Circle())
            }
            if extra > 0 {
                Text(verbatim: "+\(extra)").qText(.caption).foregroundStyle(Color.q.blueText)
                    .frame(width: size - ring * 2, height: size - ring * 2)
                    .background(Color.q.blueTint, in: Circle())
                    .padding(ring).background(Color.q.card, in: Circle())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("eventd.who"))
    }
}

/// Everyone going: open-to-meet first (the server orders them), each opens their profile.
struct EventPeopleView: View {
    let title: String
    let people: [ProfileCard]

    var body: some View {
        QList {
            ForEach(people) { p in
                NavigationLink { ProfileView(id: p.id, initial: p) } label: {
                    HStack(spacing: Sp.md) {
                        Avatar(url: p.photoURLs.first, size: 52)
                            .padding(Sp.xxs)
                            .background(p.openToMeet == true ? Color.q.gold : .clear, in: Circle())
                        VStack(alignment: .leading, spacing: Sp.xxs) {
                            Text(verbatim: "\(p.name), \(p.age)").qText(.headline).foregroundStyle(Color.q.ink)
                            if p.openToMeet == true {
                                Text(t("eventd.openOne")).qText(.footnote).foregroundStyle(Color.q.muted)
                            }
                        }
                        Spacer(minLength: 0)
                        if p.checkedIn == true {
                            QTag(label: t("events.checkedIn"), tone: .good, systemImage: "checkmark")
                        }
                    }
                }
            }
        }
        .navigationTitle(t("eventd.who"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
