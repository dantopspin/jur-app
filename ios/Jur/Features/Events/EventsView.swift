// Events as a departure board: Today / Tomorrow / Weekend. Verified members can
// create one (free, up to 50 people, 3 upcoming at a time).
import SwiftUI

struct EventsView: View {
    enum Window: String, CaseIterable, Identifiable { case today, tomorrow, weekend; var id: Self { self } }

    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @State private var events: [EventItem] = []
    @State private var loaded = false
    @State private var failed = false
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

                    if failed {
                        ErrorStateView(retry: { await load() }).frame(minHeight: 300)
                    } else if !loaded {
                        DepartureBoard(departures: (0..<3).map { _ in
                            Departure(id: UUID(), time: "19:00", title: "Падел · парная игра", place: "Padel Club", status: .onTime)
                        }, showsColumns: true)
                        .redacted(reason: .placeholder)
                        .qShimmer()
                    } else {
                        DepartureBoard(departures: shown.map(\.departure), showsColumns: !shown.isEmpty,
                                       emptyText: t("board.empty")) { d in path.append(d.id) }
                        if shown.isEmpty && canHost {
                            Button(t("board.create")) { creating = true }.buttonStyle(.q(.accent))
                        }
                    }
                }
                .padding(.horizontal, Layout.margin)
                .padding(.bottom, Sp.xl)
            }
            .animation(Motion.adaptive(Motion.smooth), value: range)
            .background(Color.q.bg)
            .navigationTitle(t("tabs.events"))
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if canHost { creating = true } else { toasts.show(t("events.verifyToHost")) }
                    } label: {
                        Image(systemName: "plus").accessibilityLabel(t("events.create"))
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                EventDetailView(eventId: id, initial: events.first { $0.id == id }) { Task { await load() } }
            }
            .refreshable { await load() }
            .task { await load() }
            .sheet(isPresented: $creating) {
                NewEventView { id in
                    Task { await load(); path.append(id) }
                }
            }
        }
    }

    private func load() async {
        failed = false
        do { events = try await Backend.upcomingEvents() } catch { failed = events.isEmpty }
        loaded = true
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
                ProgressView().padding(.top, Sp.xxl)
            }
        }
        .background(Color.q.bg)
        .navigationBarTitleDisplayMode(.inline)
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
                Haptics.success()
                toasts.show(t("events.checkedIn"))
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
