// A conversation. Text, date tickets ("ticket for two") and the nudge to stop typing
// and meet. New messages and answers arrive live (Supabase Realtime).
import Supabase
import SwiftUI

@MainActor
@Observable
final class ChatModel {
    let matchId: UUID
    var messages: [Message] = []
    var other: ProfileCard?
    var loaded = false
    var gone = false
    private var channel: RealtimeChannelV2?

    init(matchId: UUID, other: ProfileCard?) {
        self.matchId = matchId
        self.other = other
    }

    func load() async {
        do {
            messages = try await Backend.messages(matchId)
            try? await Backend.markRead(matchId)
            if other == nil {
                other = try await Backend.matches().first { $0.matchId == matchId }?.other
                if other == nil { gone = true }
            }
        } catch {
            if messages.isEmpty { gone = true }
        }
        loaded = true
    }

    func listen() async {
        let ch = supabase.channel("chat-\(matchId.uuidString.lowercased())")
        let changes = ch.postgresChange(AnyAction.self, schema: "public", table: "messages",
                                        filter: "match_id=eq.\(matchId.uuidString.lowercased())")
        channel = ch
        await ch.subscribe()
        for await _ in changes {
            if let fresh = try? await Backend.messages(matchId) {
                messages = fresh
                try? await Backend.markRead(matchId)
            }
        }
    }

    func stop() async {
        if let channel { await supabase.removeChannel(channel) }
        channel = nil
    }

    func send(_ text: String, me: UUID) async -> Bool {
        do {
            let m = try await Backend.send(text, match: matchId, from: me)
            if !messages.contains(where: { $0.id == m.id }) { messages.append(m) }
            return true
        } catch { return false }
    }

    func respond(_ m: Message, accept: Bool) async {
        _ = try? await Backend.respondDate(m.id, accept: accept)
        if let fresh = try? await Backend.messages(matchId) { messages = fresh }
    }

    /// Ten messages in a row with no date suggestion: time to meet.
    var showNudge: Bool {
        messages.count >= 10 && !messages.suffix(10).contains { $0.isDate }
    }
}

struct ChatView: View {
    let matchId: UUID
    var initial: MatchRow?
    var onChange: () -> Void = {}

    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(SportsCatalog.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @State private var model: ChatModel
    @State private var draft = ""
    @State private var sending = false
    @State private var composing = false
    @State private var reporting = false
    @State private var confirm: Confirm?
    @FocusState private var focused: Bool

    enum Confirm: Identifiable { case block, unmatch; var id: Self { self } }

    init(matchId: UUID, initial: MatchRow? = nil, onChange: @escaping () -> Void = {}) {
        self.matchId = matchId
        self.initial = initial
        self.onChange = onChange
        _model = State(initialValue: ChatModel(matchId: matchId, other: initial?.other))
    }

    var body: some View {
        Group {
            if model.gone {
                QEmptyState(symbol: "person.crop.circle.badge.xmark", title: t("chat.gone"), message: t("chat.goneSub"))
            } else {
                conversation
            }
        }
        .background(Color.q.bg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .toolbar(.hidden, for: .tabBar)
        .task { await model.load() }
        .task { await model.listen() }
        .onDisappear {
            Task { await model.stop() }
            onChange()
        }
        .sheet(isPresented: $composing) {
            DateComposerSheet(matchId: matchId, other: model.other) {
                Task { await model.load() }
            }
        }
        .sheet(isPresented: $reporting) {
            if let o = model.other { ReportSheet(name: o.name, otherId: o.id) { onChange(); dismiss() } }
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible) {
            Button(confirm == .block ? t("chat.block") : t("chat.unmatch"), role: .destructive) {
                Task { await act(confirm) }
            }
            Button(t("common.cancel"), role: .cancel) {}
        }
    }

    private var confirmTitle: String {
        let name = model.other?.name ?? ""
        return confirm == .block ? t("chat.blockConfirm", ["name": name]) : t("chat.unmatchConfirm", ["name": name])
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if let o = model.other {
                NavigationLink { ProfileView(id: o.id, initial: o) } label: {
                    HStack(spacing: Sp.sm) {
                        Avatar(url: o.photoURLs.first, size: 28)
                        Text(o.name).qText(.headline).foregroundStyle(Color.q.ink)
                        Image(systemName: "chevron.right").font(.q(.caption)).foregroundStyle(Color.q.hint)
                    }
                }
                .accessibilityLabel(t("chat.viewProfile") + ", " + o.name)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button(t("chat.report"), systemImage: "flag") { reporting = true }
                Button(t("chat.block"), systemImage: "hand.raised", role: .destructive) { confirm = .block }
                Button(t("chat.unmatch"), systemImage: "person.crop.circle.badge.minus", role: .destructive) { confirm = .unmatch }
            } label: {
                Image(systemName: "ellipsis.circle").accessibilityLabel(t("chat.menu"))
            }
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Sp.xs) {
                    if model.loaded && model.messages.isEmpty, let o = model.other {
                        Text(t("chat.start", ["name": o.name]))
                            .qText(.callout).foregroundStyle(Color.q.muted).multilineTextAlignment(.center)
                            .padding(.vertical, Sp.xl)
                    }
                    ForEach(model.messages) { m in
                        bubble(m).id(m.id)
                    }
                }
                .padding(.horizontal, Layout.margin)
                .padding(.vertical, Sp.md)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.last?.id) { _, id in
                if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
    }

    @ViewBuilder private func bubble(_ m: Message) -> some View {
        let mine = m.senderId == session.userId
        if m.isDate, let p = m.payload {
            DateTicket(
                title: p.sport.map { catalog.label($0) } ?? t("date.coffee"),
                when: p.when.flatMap { Date.iso($0) }.map(Fmt.dayTime) ?? "",
                place: p.place ?? "",
                state: p.status == "accepted" ? .accepted : p.status == "declined" ? .declined : .pending(canAnswer: !mine),
                onAccept: { Task { await model.respond(m, accept: true) } },
                onDecline: { Task { await model.respond(m, accept: false) } })
            .padding(.vertical, Sp.sm)
        } else {
            HStack {
                if mine { Spacer(minLength: 48) }
                VStack(alignment: mine ? .trailing : .leading, spacing: Sp.xxs) {
                    Text(m.isMedia ? (m.kind == "photo" ? "📷 " + t("chat2.photo") : "🎙 " + t("chat2.voice")) : m.body)
                        .qText(.body)
                        .foregroundStyle(mine ? .white : Color.q.ink)
                        .padding(.horizontal, Sp.md)
                        .padding(.vertical, Sp.sm)
                        .background(mine ? Color.q.blue : Color.q.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .textSelection(.enabled)
                    if mine, m.id == model.messages.last(where: { $0.senderId == session.userId })?.id, m.readAt != nil {
                        Text(t("chat2.read")).qText(.caption).foregroundStyle(Color.q.muted)
                    }
                }
                if !mine { Spacer(minLength: 48) }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var composer: some View {
        VStack(spacing: Sp.sm) {
            if model.showNudge {
                DateNudge { composing = true }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Layout.margin)
            }
            HStack(alignment: .bottom, spacing: Sp.sm) {
                Button { composing = true } label: {
                    Image(systemName: "calendar.badge.plus")
                        .font(.q(.headline))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.q.blue, in: Circle())
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(t("chat2.suggest"))
                TextField(t("chat.placeholder"), text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .font(.q(.body))
                    .focused($focused)
                    .padding(.horizontal, Sp.md)
                    .padding(.vertical, Sp.sm)
                    .background(Color.q.bg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Button { Task { await send() } } label: {
                    Image(systemName: "arrow.up")
                        .font(.q(.headline))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(canSend ? Color.q.blue : Color.q.hint, in: Circle())
                }
                .frame(minWidth: 44, minHeight: 44)
                .disabled(!canSend)
                .accessibilityLabel(t("chat.send"))
            }
            .padding(.horizontal, Sp.sm)
            .padding(.vertical, Sp.xs)
            .background(Color.q.card)
        }
    }

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending }

    private func send() async {
        guard let me = session.userId else { return }
        let text = draft
        draft = ""
        sending = true
        defer { sending = false }
        if !(await model.send(text, me: me)) {
            draft = text
            toasts.show(t("chat.sendFailed"), error: true)
        }
    }

    private func act(_ c: Confirm?) async {
        guard let c, let me = session.userId else { return }
        do {
            switch c {
            case .block: if let o = model.other { try await Backend.block(o.id, me: me) }
            case .unmatch: try await Backend.unmatch(matchId)
            }
            onChange()
            dismiss()
        } catch { toasts.show(t("common.error"), error: true) }
    }
}

/// "Suggest a date": what, when, where. They answer with one tap.
struct DateComposerSheet: View {
    let matchId: UUID
    let other: ProfileCard?
    let onSent: () -> Void
    @Environment(SportsCatalog.self) private var catalog
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var sport: String?
    @State private var when = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var place = ""
    @State private var busy = false
    @State private var error: String?

    private var options: [String] { (other?.sports ?? []).map(\.code) }

    var body: some View {
        NavigationStack {
            Form {
                Section(t("date.sport")) {
                    Picker(t("date.sport"), selection: $sport) {
                        Text("☕️ " + t("date.coffee")).tag(String?.none)
                        ForEach(options, id: \.self) { code in Text(catalog.label(code)).tag(String?.some(code)) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section(t("date.when")) {
                    DatePicker(t("date.when"), selection: $when, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                        .environment(\.timeZone, Fmt.zone)
                }
                Section(t("date.where")) {
                    TextField(t("date.wherePlaceholder"), text: $place)
                }
                if let error {
                    Section { Text(error).foregroundStyle(Color.q.danger) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.q.bg)
            .navigationTitle(t("date.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(t("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("date.sendShort")) { Task { await send() } }
                        .disabled(place.trimmingCharacters(in: .whitespaces).count < 3 || busy)
                }
            }
        }
        .qSheet(detents: [.large])
    }

    private func send() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let r = try await Backend.proposeDate(match: matchId, sport: sport, when: when, place: place)
            if r.ok {
                Haptics.success()
                onSent()
                dismiss()
            } else {
                error = t("date.invalid")
            }
        } catch { error = t("common.error") }
    }
}

/// Report: pick a reason; the person is also blocked.
struct ReportSheet: View {
    let name: String
    let otherId: UUID
    let onDone: () -> Void
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false

    private let reasons = ["fake", "inappropriate", "harassment", "underage", "scam", "other"]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(reasons, id: \.self) { r in
                        Button { Task { await report(r) } } label: {
                            Text(t("report.\(r)")).qText(.body).foregroundStyle(Color.q.ink)
                        }
                        .disabled(busy)
                    }
                } header: {
                    Text(t("report.title", ["name": name])).qText(.callout).textCase(nil)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.q.bg)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(t("common.cancel")) { dismiss() } }
            }
        }
        .qSheet(detents: [.medium, .large])
    }

    private func report(_ reason: String) async {
        guard let me = session.userId else { return }
        busy = true
        defer { busy = false }
        do {
            try await Backend.report(otherId, me: me, reason: reason, details: nil)
            try await Backend.block(otherId, me: me)
            toasts.show(t("report.thanks"))
            dismiss()
            onDone()
        } catch { toasts.show(t("common.error"), error: true) }
    }
}
