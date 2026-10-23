// Who liked you. Pro sees the people (and their notes); free members see the count
// with blurred tiles and a way to Pro.
import SwiftUI

struct LikesView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @State private var likes: LikesReceived? = DataCache.get(CacheKey.likes, as: LikesReceived.self)
    @State private var failed = false
    @State private var paywall = false
    /// People just liked back: their tiles turn over into match tiles before the list refreshes.
    @State private var matched: Set<UUID> = []
    @Namespace private var zoom

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
                                    .qZoomDestination(id: p.id, in: zoom)
                            } label: {
                                LikeTile(card: p, matched: matched.contains(p.id)) { tile(p) }
                                    .qZoomSource(id: p.id, in: zoom)
                            }
                            .buttonStyle(.qPressCard)
                            .disabled(matched.contains(p.id))
                        }
                    }
                    .padding(Layout.margin)
                }
            } else if failed {
                ErrorStateView(retry: { await load() }).frame(minHeight: 420)
            } else {
                AfterABlink { SkeletonTiles() }
            }
        }
        .background(Color.q.bg)
        .navigationTitle(t("likes.title"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $paywall) { PaywallView(context: .likes(count: likes?.count ?? 0)) }
    }

    private func tile(_ p: ProfileCard) -> some View {
        Color.q.line
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay { QPhoto(url: p.photoURLs.first, size: .thumb) }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: Sp.xxs) {
                    if p.superLikedMe == true { QTag(label: t("discover.superLikedYou"), tone: .gold, systemImage: "star.fill") }
                    Text("\(p.name), \(p.age)").qText(.headline).foregroundStyle(.white)
                    if let n = p.note, !n.isEmpty { Text("“\(n)”").qText(.footnote).foregroundStyle(.white).lineLimit(2) }
                }
                .padding(Sp.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, Color.q.scrim], startPoint: .top, endPoint: .bottom))
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
            if r.error == "like_limit" { paywall = true }
            if r.matchId != nil {
                // Back on the grid first, so the turn is seen.
                try? await Task.sleep(for: .milliseconds(350))
                matched.insert(p.id)
                Haptics.success()
                Sounds.play(.match)
                try? await Task.sleep(for: .seconds(2.4))
            }
            await load()
            matched.remove(p.id)
        } catch { toasts.show(error) }
    }
}

/// A Likes tile that, once liked back, turns over into a match tile: blue, their photo in
/// a gold ring, the gold tick drawing itself in, "В одном темпе!".
private struct LikeTile<Front: View>: View {
    let card: ProfileCard
    let matched: Bool
    @ViewBuilder let front: () -> Front
    @State private var showBack = false
    @State private var angle: Double = 0

    var body: some View {
        ZStack {
            front().modifier(FlipFace(angle: angle, back: false))
            if showBack {
                back.modifier(FlipFace(angle: angle, back: true))
            }
        }
        .onChange(of: matched) { _, now in
            guard now else { return }
            // The back goes in face-down first, then the tile turns.
            showBack = true
            DispatchQueue.main.async {
                withAnimation(Motion.reduceMotion ? Motion.fade : Motion.flip) { angle = 180 }
            }
        }
    }

    private var back: some View {
        Color.q.blue
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                VStack(spacing: Sp.md) {
                    Avatar(url: card.photoURLs.first, size: 84)
                        .overlay(Circle().stroke(Color.q.gold, lineWidth: 3))
                        .overlay(alignment: .bottomTrailing) { SelectedTick(size: 30, delay: 0.45).offset(x: 4, y: 4) }
                    Text(t("match.title"))
                        .qText(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(t("likes.nowMatched"))
                        .qText(.footnote)
                        .foregroundStyle(Color.q.blueMist)
                        .multilineTextAlignment(.center)
                }
                .padding(Sp.md)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .accessibilityElement(children: .combine)
    }
}

/// One face of a tile turning over: the front shows until it's edge-on, then the back.
private struct FlipFace: ViewModifier, Animatable {
    var angle: Double
    let back: Bool
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let reduce = Motion.reduceMotion
        let showing = back ? angle >= 90 : angle < 90
        return content
            .rotation3DEffect(.degrees(reduce ? 0 : (back ? angle - 180 : angle)), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .opacity(reduce ? (back ? angle / 180 : 1 - angle / 180) : (showing ? 1 : 0))
    }
}
