// Pairs: who liked you (a row into Likes), then your matches, newest conversation first.
import SwiftUI

@MainActor
@Observable
final class PairsModel {
    /// Last time's lists first, so the tab never opens empty.
    var rows: [MatchRow] = DataCache.get(CacheKey.matches, as: [MatchRow].self) ?? []
    var likes = DataCache.get(CacheKey.likes, as: LikesReceived.self)?.count ?? 0
    var loaded = DataCache.get(CacheKey.matches, as: [MatchRow].self) != nil
    var failed = false
    var unread: Int { rows.reduce(0) { $0 + $1.unread } }

    func load() async {
        failed = false
        do {
            async let m = Backend.matches()
            async let l = Backend.likesReceived()
            let (rows, likes) = try await (m, l)
            self.rows = rows
            self.likes = likes.count
            ImageLoader.shared.prefetch(rows.compactMap { $0.other.photoURLs.first }, .thumb)
        } catch {
            failed = rows.isEmpty
        }
        loaded = true
    }

    /// Swipe → "Read": the badge goes at once; the server follows.
    func markRead(_ row: MatchRow) async {
        guard let i = rows.firstIndex(where: { $0.matchId == row.matchId }) else { return }
        let before = rows[i].unread
        withMotion(Motion.snappy) { rows[i].unread = 0 }
        do { try await Backend.markRead(row.matchId) }
        catch { if let j = rows.firstIndex(where: { $0.matchId == row.matchId }) { rows[j].unread = before } }
    }

    /// Unmatch from the list: the row leaves at once and comes back if the server says no.
    func unmatch(_ row: MatchRow, toasts: ToastCenter) async {
        guard let i = rows.firstIndex(where: { $0.matchId == row.matchId }) else { return }
        withMotion(Motion.smooth) { _ = rows.remove(at: i) }
        do {
            try await Backend.unmatch(row.matchId)
        } catch {
            withMotion(Motion.smooth) { rows.insert(row, at: min(i, rows.count)) }
            toasts.show(error)
        }
    }
}

struct PairsView: View {
    @Bindable var model: PairsModel
    @Binding var path: [UUID]
    @Binding var showLikes: Bool
    var goDiscover: () -> Void = {}
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @State private var unmatching: MatchRow?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if model.likes > 0 {
                    NavigationLink { LikesView() } label: {
                        HStack(spacing: Sp.md) {
                            Image(systemName: "heart.fill").font(.q(.title3)).foregroundStyle(Color.q.gold)
                                .frame(width: 52, height: 52).background(Color.q.blueNight, in: Circle())
                            VStack(alignment: .leading, spacing: Sp.xxs) {
                                Text(model.likes == 1 ? t("matches.likedYouOne") : t("matches.likedYou", ["n": model.likes]))
                                    .qText(.headline)
                                    .contentTransition(.numericText())
                                    .animation(Motion.snappy, value: model.likes)
                                Text(t("matches.seeWho")).qText(.footnote).foregroundStyle(Color.q.blueText)
                            }
                        }
                    }
                }
                ForEach(model.rows) { row in
                    NavigationLink(value: row.matchId) { MatchRowView(row: row, me: session.userId) }
                        .swipeActions(edge: .leading) {
                            if row.unread > 0 {
                                Button { Task { await model.markRead(row) } } label: {
                                    Label(t("matches.markRead"), systemImage: "envelope.open")
                                }
                                .tint(Color.q.blue)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { unmatching = row } label: {
                                Label(t("chat.unmatch"), systemImage: "person.crop.circle.badge.minus")
                            }
                            .tint(Color.q.danger)
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.q.bg)
            .overlay {
                if model.loaded && model.rows.isEmpty && model.likes == 0 {
                    PairsEmpty(goDiscover: goDiscover)
                } else if model.failed {
                    ErrorStateView(retry: { await model.load() })
                } else if !model.loaded {
                    AfterABlink { SkeletonRows() }
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .confirmationDialog(t("chat.unmatchConfirm", ["name": unmatching?.other.name ?? ""]),
                                isPresented: Binding(get: { unmatching != nil }, set: { if !$0 { unmatching = nil } }),
                                titleVisibility: .visible) {
                Button(t("chat.unmatch"), role: .destructive) {
                    if let r = unmatching { Task { await model.unmatch(r, toasts: toasts) } }
                }
                Button(t("common.cancel"), role: .cancel) {}
            }
            .navigationTitle(t("tabs.matches"))
            .toolbarTitleDisplayMode(.inlineLarge)
            .navigationDestination(for: UUID.self) { id in
                ChatView(matchId: id, initial: model.rows.first { $0.matchId == id }) {
                    Task { await model.load() }
                }
            }
            .navigationDestination(isPresented: $showLikes) { LikesView() }
            .refreshable { await model.load() }
            .task { await model.load() }
        }
    }
}

struct MatchRowView: View {
    let row: MatchRow
    let me: UUID?

    var body: some View {
        HStack(spacing: Sp.md) {
            Avatar(url: row.other.photoURLs.first, size: 52)
            VStack(alignment: .leading, spacing: Sp.xxs) {
                HStack {
                    Text(row.other.name).qText(.headline).foregroundStyle(Color.q.ink).lineLimit(1)
                    Spacer(minLength: Sp.sm)
                    if let last = row.lastMessage, let d = Date.iso(last.createdAt) {
                        Text(Fmt.relative(d)).qText(.caption).foregroundStyle(Color.q.muted).fixedSize()
                    }
                }
                HStack {
                    Text(preview).qText(.callout).foregroundStyle(row.unread > 0 ? Color.q.ink : Color.q.muted).lineLimit(1)
                    Spacer()
                    if row.unread > 0 {
                        Text("\(row.unread)").qText(.label).foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .padding(.horizontal, Sp.sm).padding(.vertical, Sp.xxs)
                            .background(Color.q.blue, in: Capsule())
                            .fixedSize()
                            .transition(.qPop)
                    }
                }
            }
        }
        .padding(.vertical, Sp.xs)
        .animation(Motion.adaptive(Motion.snappy), value: row.unread)
        .accessibilityElement(children: .combine)
    }

    private var preview: String {
        guard let last = row.lastMessage else { return t("matches.newMatch") }
        let mine = last.senderId == me ? t("matches.you") : ""
        switch last.kind {
        case "date": return mine + t("chat2.dateCard")
        case "photo": return mine + t("chat2.photo")
        case "voice": return mine + t("chat2.voice")
        default: return mine + last.body
        }
    }
}
