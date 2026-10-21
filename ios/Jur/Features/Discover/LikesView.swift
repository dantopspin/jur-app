// Who liked you. Pro sees the people (and their notes); free members see the count
// with blurred tiles and a way to Pro.
import SwiftUI

struct LikesView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @State private var likes: LikesReceived?
    @State private var failed = false
    @State private var paywall = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Sp.md), count: 2)

    var body: some View {
        ScrollView {
            if let likes {
                if likes.count == 0 {
                    QEmptyState(symbol: "heart", title: t("likes.empty"),
                                message: t(Config.eventsEnabled ? "likes.emptySub" : "likes.emptySubApp"))
                        .frame(minHeight: 420)
                } else if likes.profiles.isEmpty {
                    locked(count: likes.count)
                } else {
                    LazyVGrid(columns: columns, spacing: Sp.md) {
                        ForEach(likes.profiles) { p in
                            NavigationLink {
                                ProfileView(id: p.id, initial: p) { kind in Task { await decide(p, kind) } }
                            } label: { tile(p) }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(Layout.margin)
                }
            } else if failed {
                ErrorStateView(retry: { await load() }).frame(minHeight: 420)
            } else {
                ProgressView().padding(.top, Sp.xxl)
            }
        }
        .background(Color.q.bg)
        .navigationTitle(t("likes.title"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $paywall) { PaywallView() }
    }

    private func tile(_ p: ProfileCard) -> some View {
        Color.q.line
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay { QPhoto(url: p.photoURLs.first) }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: Sp.xxs) {
                    if p.superLikedMe == true { QTag(label: t("discover.superLikedYou"), tone: .gold, systemImage: "star.fill") }
                    Text("\(p.name), \(p.age)").qText(.headline).foregroundStyle(.white)
                    if let n = p.note, !n.isEmpty { Text("“\(n)”").qText(.footnote).foregroundStyle(.white).lineLimit(2) }
                }
                .padding(Sp.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .accessibilityElement(children: .combine)
    }

    private func locked(count: Int) -> some View {
        VStack(spacing: Sp.xl) {
            LazyVGrid(columns: columns, spacing: Sp.md) {
                ForEach(0..<min(count, 4), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(LinearGradient(colors: [Color.q.blueDeep, Color.q.blue], startPoint: .top, endPoint: .bottom))
                        .aspectRatio(3 / 4, contentMode: .fit)
                        .overlay(Image(systemName: "heart.fill").font(.q(.title1)).foregroundStyle(Color.q.gold))
                }
            }
            .accessibilityHidden(true)
            Text(count == 1 ? t("matches.likedYouOne") : t("matches.likedYou", ["n": count]))
                .qText(.title3).multilineTextAlignment(.center)
            Text(t("likes.proOnly")).qText(.body).foregroundStyle(Color.q.inkSoft).multilineTextAlignment(.center)
            Button(t("me.getPro")) { paywall = true }.buttonStyle(.q(.accent))
        }
        .padding(Layout.margin)
    }

    private func load() async {
        failed = false
        do { likes = try await Backend.likesReceived() } catch { if likes == nil { failed = true } }
    }

    private func decide(_ p: ProfileCard, _ kind: SwipeKind) async {
        do {
            let r = try await Backend.swipe(p.id, kind)
            if r.matchId != nil { toasts.show(t("match.title")) }
            if r.error == "like_limit" { paywall = true }
            await load()
        } catch { toasts.show(t("common.error"), error: true) }
    }
}
