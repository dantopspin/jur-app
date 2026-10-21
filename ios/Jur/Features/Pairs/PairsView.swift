// Pairs: who liked you (a row into Likes), then your matches, newest conversation first.
import SwiftUI

@MainActor
@Observable
final class PairsModel {
    var rows: [MatchRow] = []
    var likes = 0
    var loaded = false
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
        } catch {
            failed = rows.isEmpty
        }
        loaded = true
    }
}

struct PairsView: View {
    @Bindable var model: PairsModel
    @Binding var path: [UUID]
    var goDiscover: () -> Void = {}
    @Environment(SessionStore.self) private var session

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
                                Text(t("matches.seeWho")).qText(.footnote).foregroundStyle(Color.q.blueText)
                            }
                        }
                    }
                }
                ForEach(model.rows) { row in
                    NavigationLink(value: row.matchId) { MatchRowView(row: row, me: session.userId) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.q.bg)
            .overlay {
                if model.loaded && model.rows.isEmpty && model.likes == 0 {
                    QEmptyState(symbol: "bubble.left.and.bubble.right", title: t("matches.empty"),
                                message: t("matches.emptySubApp"), actionTitle: t("matches.goDiscover"), action: goDiscover)
                } else if model.failed {
                    ErrorStateView(retry: { await model.load() })
                } else if !model.loaded {
                    ProgressView()
                }
            }
            .navigationTitle(t("tabs.matches"))
            .toolbarTitleDisplayMode(.inlineLarge)
            .navigationDestination(for: UUID.self) { id in
                ChatView(matchId: id, initial: model.rows.first { $0.matchId == id }) {
                    Task { await model.load() }
                }
            }
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
                    Text(row.other.name).qText(.headline).foregroundStyle(Color.q.ink)
                    Spacer()
                    if let last = row.lastMessage, let d = Date.iso(last.createdAt) {
                        Text(Fmt.relative(d)).qText(.caption).foregroundStyle(Color.q.muted)
                    }
                }
                HStack {
                    Text(preview).qText(.callout).foregroundStyle(row.unread > 0 ? Color.q.ink : Color.q.muted).lineLimit(1)
                    Spacer()
                    if row.unread > 0 {
                        Text("\(row.unread)").qText(.label).foregroundStyle(.white)
                            .padding(.horizontal, Sp.sm).padding(.vertical, Sp.xxs)
                            .background(Color.q.blue, in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, Sp.xs)
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
