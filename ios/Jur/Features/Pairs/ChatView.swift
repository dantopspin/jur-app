// A conversation. Text, date tickets ("ticket for two") and the nudge to stop typing
// and meet. New messages and answers arrive live (Supabase Realtime).
import PhotosUI
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

    /// New messages animate in once the first load is done; the first load doesn't.
    private func apply(_ fresh: [Message]) {
        guard fresh != messages else { return }
        if loaded { withMotion(Motion.smooth) { messages = fresh } } else { messages = fresh }
    }

    func load() async {
        do {
            apply(try await Backend.messages(matchId))
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
                                        filter: .eq("match_id", value: matchId.uuidString.lowercased()))
        channel = ch
        do { try await ch.subscribeWithError() } catch { return }
        for await _ in changes {
            if let fresh = try? await Backend.messages(matchId) {
                apply(fresh)
                try? await Backend.markRead(matchId)
            }
        }
    }

    func stop() async {
        if let channel { await supabase.removeChannel(channel) }
        channel = nil
    }

    func send(_ text: String, me: UUID, replyTo: UUID? = nil) async -> Bool {
        do {
            let m = try await Backend.send(text, match: matchId, from: me, replyTo: replyTo)
            if !messages.contains(where: { $0.id == m.id }) { withMotion(Motion.smooth) { messages.append(m) } }
            return true
        } catch { return false }
    }

    func react(_ m: Message, _ reaction: String) async {
        try? await Backend.react(m.id, reaction)
        if let fresh = try? await Backend.messages(matchId) { apply(fresh) }
    }

    func respond(_ m: Message, accept: Bool) async {
        _ = try? await Backend.respondDate(m.id, accept: accept)
        if let fresh = try? await Backend.messages(matchId) { apply(fresh) }
    }

    /// Photos unlock once both people have written a text message (the server enforces it too).
    func photosUnlocked(me: UUID?) -> Bool {
        let texts = messages.filter { ($0.kind ?? "text") == "text" }
        return texts.contains { $0.senderId == me } && texts.contains { $0.senderId != me }
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
    @State private var pickingPhoto = false
    @State private var photoItem: PhotosPickerItem?
    @State private var uploading = false
    @State private var recorder = VoiceRecorder()
    @State private var replyingTo: Message?
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
            recorder.cancel()
            VoicePlayer.shared.stop()
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
                        Text(o.name).qText(.headline).foregroundStyle(Color.q.ink).lineLimit(1)
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
                            .transition(.qBubble(mine: m.senderId == session.userId))
                    }
                }
                .padding(.horizontal, Layout.margin)
                .padding(.vertical, Sp.md)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.last?.id) { _, id in
                if let id { withMotion(Motion.smooth) { proxy.scrollTo(id, anchor: .bottom) } }
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
                onAccept: { Haptics.success(); Task { await model.respond(m, accept: true) } },
                onDecline: { Task { await model.respond(m, accept: false) } })
            .padding(.vertical, Sp.sm)
        } else if m.isPhoto || m.isVoice {
            HStack {
                if mine { Spacer(minLength: 48) }
                if m.isPhoto { PhotoBubble(message: m, mine: mine) } else { VoiceBubble(message: m, mine: mine) }
                if !mine { Spacer(minLength: 48) }
            }
        } else {
            HStack {
                if mine { Spacer(minLength: 48) }
                VStack(alignment: mine ? .trailing : .leading, spacing: Sp.xxs) {
                    VStack(alignment: .leading, spacing: Sp.xs) {
                        if let r = m.reply {
                            Text(r.kind == "photo" ? t("chat2.photo") : r.kind == "voice" ? t("chat2.voice") : r.body)
                                .qText(.footnote)
                                .lineLimit(2)
                                .foregroundStyle(mine ? Color.white.opacity(0.85) : Color.q.inkSoft)
                                .padding(.leading, Sp.sm)
                                .overlay(alignment: .leading) {
                                    Rectangle().fill(mine ? Color.white.opacity(0.6) : Color.q.blueText).frame(width: 2)
                                }
                        }
                        Text(m.body)
                            .qText(.body)
                            .foregroundStyle(mine ? .white : Color.q.ink)
                    }
                    .padding(.horizontal, Sp.md)
                    .padding(.vertical, Sp.sm)
                    .background(mine ? Color.q.blue : Color.q.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .contextMenu { messageMenu(m) }
                    reactionsRow(m, mine: mine)
                    if mine, m.id == model.messages.last(where: { $0.senderId == session.userId })?.id, m.readAt != nil {
                        Text(t("chat2.read")).qText(.caption).foregroundStyle(Color.q.muted)
                            .transition(.qPop)
                    }
                }
                if !mine { Spacer(minLength: 48) }
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private func messageMenu(_ m: Message) -> some View {
        Button(t("chat2.reply"), systemImage: "arrowshape.turn.up.left") { replyingTo = m; focused = true }
        Button(t("chat2.copy"), systemImage: "doc.on.doc") { UIPasteboard.general.string = m.body }
        Divider()
        ForEach(Reactions.all, id: \.key) { r in
            Button(r.emoji) { Haptics.tick(); Task { await model.react(m, r.key) } }
        }
    }

    @ViewBuilder private func reactionsRow(_ m: Message, mine: Bool) -> some View {
        let list = m.reactions ?? []
        if !list.isEmpty {
            HStack(spacing: Sp.xxs) {
                ForEach(Array(Set(list.map(\.reaction))).sorted(), id: \.self) { key in
                    let count = list.filter { $0.reaction == key }.count
                    HStack(spacing: Sp.xxs) {
                        Text(Reactions.emoji(key))
                        if count > 1 { Text("\(count)").monospacedDigit().contentTransition(.numericText()) }
                    }
                    .qText(.caption)
                    .padding(.horizontal, Sp.sm).padding(.vertical, Sp.xxs)
                    .background(Color.q.card, in: Capsule())
                    .overlay(Capsule().stroke(Color.q.line, lineWidth: 1))
                    .onTapGesture { Haptics.tick(); Task { await model.react(m, key) } }
                    .transition(.qPop)
                }
            }
            .accessibilityElement(children: .combine)
            .transition(.qPop)
        }
    }

    private var composer: some View {
        VStack(spacing: Sp.sm) {
            if model.showNudge {
                DateNudge { composing = true }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Layout.margin)
                    .transition(.qRise)
            }
            if let r = replyingTo {
                HStack(spacing: Sp.sm) {
                    Rectangle().fill(Color.q.blueText).frame(width: 2)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(t("chat2.replyingTo", ["name": r.senderId == session.userId ? t("chat2.you") : (model.other?.name ?? "")]))
                            .qText(.caption).foregroundStyle(Color.q.blueText)
                        Text(r.body.isEmpty ? t("chat2.photo") : r.body).qText(.footnote).foregroundStyle(Color.q.inkSoft).lineLimit(1)
                    }
                    Spacer()
                    Button { replyingTo = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.q.hint) }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel(t("common.cancel"))
                }
                .frame(minHeight: 44)
                .padding(.vertical, Sp.xxs)
                .padding(.horizontal, Layout.margin)
                .background(Color.q.card)
                .transition(.qRise)
            }
            if let started = recorder.started {
                RecordingBar(started: started, onCancel: { recorder.cancel() }, onSend: { Task { await sendVoice() } })
                    .padding(.vertical, Sp.xs)
                    .background(Color.q.card)
                    .transition(.opacity)
            } else {
                inputRow
                    .transition(.opacity)
            }
        }
        .animation(Motion.adaptive(Motion.smooth), value: model.showNudge)
        .animation(Motion.adaptive(Motion.smooth), value: replyingTo?.id)
        .animation(Motion.adaptive(Motion.smooth), value: recorder.started)
        .photosPicker(isPresented: $pickingPhoto, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await sendPhoto(item) }
        }
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: Sp.sm) {
            Menu {
                Button(t("chat2.suggest"), systemImage: "calendar.badge.plus") { composing = true }
                Button(t("chat2.photo") + (model.photosUnlocked(me: session.userId) ? "" : " · " + t("safety.photosLocked")),
                       systemImage: "photo") {
                    if model.photosUnlocked(me: session.userId) { pickingPhoto = true }
                    else { toasts.show(t("safety.photosLockedSub")) }
                }
            } label: {
                Group {
                    if uploading { ProgressView().tint(.white) } else { Image(systemName: "plus").font(.q(.headline)) }
                }
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.q.blue, in: Circle())
            }
            .frame(minWidth: 44, minHeight: 44)
            .disabled(uploading)
            .accessibilityLabel(t("chat2.attach"))
            TextField(t("chat.placeholder"), text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .font(.q(.body))
                .focused($focused)
                .padding(.horizontal, Sp.md)
                .padding(.vertical, Sp.sm)
                .background(Color.q.bg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            micOrSend
        }
        .padding(.horizontal, Sp.sm)
        .padding(.vertical, Sp.xs)
        .background(Color.q.card)
    }

    /// Mic while the field is empty, send once there's text: one button whose symbol morphs.
    private var micOrSend: some View {
        let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button {
            if empty { Task { await startRecording() } } else { Task { await send() } }
        } label: {
            Image(systemName: empty ? "mic.fill" : "arrow.up")
                .font(.q(.headline))
                .foregroundStyle(empty ? Color.q.blueText : .white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 36)
                .background(empty ? Color.q.blueTint : (canSend ? Color.q.blue : Color.q.hint), in: Circle())
        }
        .buttonStyle(.qPress)
        .frame(minWidth: 44, minHeight: 44)
        .disabled(!empty && !canSend)
        .accessibilityLabel(empty ? t("chat2.mic") : t("chat.send"))
        .animation(Motion.snappy, value: empty)
    }

    private func sendPhoto(_ item: PhotosPickerItem) async {
        guard let me = session.userId else { return }
        uploading = true
        defer { uploading = false; photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            try await ChatMedia.sendPhoto(data, match: matchId, me: me)
            await model.load()
        } catch let e as ServerError where e.code == "photo_too_soon" {
            toasts.show(t("safety.photosLockedSub"))
        } catch {
            toasts.show(t("chat.sendFailed"), error: true)
        }
    }

    private func startRecording() async {
        focused = false
        if await recorder.start() { Haptics.knock() } else { toasts.show(t("chat2.micDenied"), error: true) }
    }

    private func sendVoice() async {
        guard let me = session.userId, let rec = recorder.finish() else { return }
        uploading = true
        defer { uploading = false }
        do {
            try await ChatMedia.sendVoice(rec.url, durationMs: rec.ms, match: matchId, me: me)
            try? FileManager.default.removeItem(at: rec.url)
            await model.load()
        } catch {
            toasts.show(t("chat.sendFailed"), error: true)
        }
    }

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending }

    private func send() async {
        guard let me = session.userId else { return }
        let text = draft
        let reply = replyingTo?.id
        draft = ""
        replyingTo = nil
        sending = true
        defer { sending = false }
        if !(await model.send(text, me: me, replyTo: reply)) {
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
        } catch { self.error = t("common.error") }
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
