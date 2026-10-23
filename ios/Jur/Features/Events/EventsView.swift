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

    private func load() async {
        failed = false
        do { events = try await Backend.upcomingEvents() } catch { failed = true }
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

    private var isHost: Bool { event?.hostId != nil && event?.hostId == session.userId }

    var body: some View {
        ScrollView {
            if let e = event {
                VStack(alignment: .leading, spacing: Sp.lg) {
                    DepartureBoard(departures: [e.departure], header: catalog.label(e.sportCode))
                    VStack(alignment: .leading, spacing: Sp.md) {
                        Text(e.title).qText(.title2).foregroundStyle(Color.q.ink).accessibilityAddTraits(.isHeader)
                        info("clock", Fmt.dayTime(e.start) + " · " + t("events.durationMin", ["n": e.durationMin]))
                        info("mappin.and.ellipse", e.meetingPoint)
                        info("person.2", t("events.going", ["n": e.goingCount, "cap": e.capacity]))
                        if let h = e.host { info("person.crop.circle", t("events.host", ["name": h.name])) }
                        if let d = e.description, !d.isEmpty {
                            Text(d).qText(.body).foregroundStyle(Color.q.ink).padding(.top, Sp.sm)
                        }
                    }
                    .qCard()
                    if isHost { hostCard(e) }
                    actions(e)
                }
                .padding(Layout.margin)
            } else {
                AfterABlink { MarkLoader().padding(.top, Sp.xxl) }
            }
        }
        .background(Color.q.bg)
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
        .sheet(isPresented: $boarding) {
            BoardingCodeSheet(eventTitle: event.map { "\($0.title) \(Fmt.time($0.start))" } ?? "",
                              code: $code, busy: busy, isError: codeError) {
                Task { await checkIn() }
            }
        }
    }

    private func info(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).qText(.callout).foregroundStyle(Color.q.inkSoft)
    }

    @ViewBuilder private func actions(_ e: EventItem) -> some View {
        if e.iCheckedIn {
            QTag(label: t("events.checkedIn"), tone: .good, systemImage: "checkmark").transition(.qPop)
        } else if e.iAmGoing {
            if e.boardingOpen && !isHost {
                Button(t("board.codeGo")) { code = ""; codeError = false; boarding = true }.buttonStyle(.qPrimary)
            } else if !isHost {
                Text(t("events.notNow")).qText(.footnote).foregroundStyle(Color.q.muted)
            }
            if !isHost {
                Button(t("events.leave")) { Task { await leave() } }.buttonStyle(.qGhost).disabled(busy)
            }
        } else if e.isFull {
            QTag(label: t("events.full"), tone: .neutral).transition(.qPop)
        } else {
            Button { Task { await join() } } label: { BusyLabel(title: t("events.join"), busy: busy) }
                .buttonStyle(.qPrimary).disabled(busy)
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
                    .animation(Motion.snappy, value: left)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .qCard()
            .onChange(of: left == 60) { _, minuteTurned in if minuteTurned { reloadTick += 1 } }
        }
        .task(id: reloadTick) { hostCode = (try? await Backend.hostCode(e.id))?.code }
    }

    private func load() async {
        guard let fresh = try? await Backend.event(eventId) else { return }
        if event == nil { event = fresh } else { withMotion(Motion.smooth) { event = fresh } }
    }

    private func join() async {
        guard let e = event else { return }
        busy = true
        defer { busy = false }
        do {
            let r = try await Backend.joinEvent(e.id)
            if r.ok { Haptics.success(); toasts.show(t("events.youreIn")) }
            else { toasts.show(t(r.error == "full" ? "events.full" : "common.error"), error: true) }
            await load()
            onChange()
        } catch { toasts.show(t("common.error"), error: true) }
    }

    private func leave() async {
        guard let e = event else { return }
        busy = true
        defer { busy = false }
        try? await Backend.leaveEvent(e.id)
        await load()
        onChange()
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
                toasts.show(t(r.error == "not_now" ? "events.notNow" : "board.badCode"), error: true)
            }
        } catch { toasts.show(t("common.error"), error: true) }
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

    private var valid: Bool {
        title.trimmingCharacters(in: .whitespaces).count >= 3 && !sport.isEmpty
            && place.trimmingCharacters(in: .whitespaces).count >= 3 && start > .now
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(t("events.fieldTitle"), text: $title)
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
                    TextField(t("events.fieldMeeting"), text: $place)
                    TextField(t("events.fieldDescription"), text: $about, axis: .vertical).lineLimit(3...8)
                } footer: {
                    Text(t("events.memberRules")).qText(.footnote)
                }
                if let error { Section { Text(error).foregroundStyle(Color.q.danger) } }
            }
            .scrollContentBackground(.hidden)
            .background(Color.q.bg)
            .navigationTitle(t("events.create"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(t("common.cancel")) { dismiss() } }
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

/// Check-in's moment: the "showed up" stamp lands on a felt card with a thump, then
/// clears itself (or on tap).
struct StampLanding: View {
    let data: StampData
    var city: String?
    let onDone: () -> Void
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: Sp.lg) {
                Stamp(data: data, city: city)
                    .scaleEffect(landed || reduceMotion ? 1 : 1.4)
                    .rotationEffect(.degrees(landed || reduceMotion ? 0 : -12))
                    .opacity(landed ? 1 : 0)
                Text(t("events.checkedIn")).qText(.headline).foregroundStyle(Color.q.feltInk)
            }
            .padding(Sp.xxl)
            .background(Color.q.feltGround, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .qElevated()
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDone)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isModal)
        .task {
            withAnimation(Motion.adaptive(Motion.bouncy)) { landed = true }
            try? await Task.sleep(for: .seconds(0.15))
            Haptics.thump()
            Haptics.success()
            Sounds.play(.checkin)
            try? await Task.sleep(for: .seconds(1.8))
            onDone()
        }
    }
}
