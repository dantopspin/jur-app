// A person: photos with a page indicator, name and age, the verified mark, the meta
// line (№ · city · departures), sports, and their words. Used in Discover (as a card),
// Likes, picks and the full profile.
import SwiftUI
import TipKit

struct ProfileCardView: View {
    let card: ProfileCard
    /// Discover's card: a shorter photo and only the first lines of text.
    var compact = false
    /// Only the deck's top card shows first-session hints.
    var showsTips = false
    @Environment(SportsCatalog.self) private var catalog
    @State private var page = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            photos
            VStack(alignment: .leading, spacing: Sp.md) {
                HStack(alignment: .firstTextBaseline, spacing: Sp.xs) {
                    Text("\(card.name), \(card.age)").qText(.title2).foregroundStyle(Color.q.ink).lineLimit(2)
                    if card.verified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.q(.headline))
                            .foregroundStyle(Color.q.blueText)
                            .accessibilityLabel(t("card.verified"))
                    }
                    Spacer(minLength: 0)
                }
                Text(meta).qText(.callout).foregroundStyle(Color.q.inkSoft).monospacedDigit()
                if let sports = card.sports, !sports.isEmpty {
                    FlowLayout(spacing: Sp.xs) {
                        ForEach(sports, id: \.code) { s in
                            QTag(label: catalog.label(s.code), tone: .neutral)
                        }
                    }
                }
                if !compact { words }
            }
            .padding(Sp.lg)
        }
        .background(Color.q.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var meta: String {
        // No member number here: a low one only tells strangers the app is new.
        // It stays on the passport, where the "founding" stamp explains what early means.
        var parts = [Cities.label(card.travelCity ?? card.city)]
        if let n = card.eventsAttended, n > 0, Config.eventsEnabled { parts.append(t("passport.departures") + " " + String(n)) }
        return parts.joined(separator: " · ")
    }

    private var photos: some View {
        let urls = card.photoURLs
        return ZStack(alignment: .top) {
            Color.q.blueDeep
            if urls.isEmpty {
                Image(systemName: "person.fill").font(.system(size: IconSize.hero)).foregroundStyle(Color.q.blueMist)
            } else {
                // The deep-blue ground shows while a photo loads; the card's other photos are
                // fetched in the background so tapping through them is instant.
                QPhoto(url: urls[min(page, urls.count - 1)], placeholder: Color.clear)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .id(page)
                    .transition(.opacity)
                    .task(id: card.id) { ImageLoader.shared.prefetch(urls, .full) }
            }
            // Page bars + tap zones (left half back, right half forward).
            if urls.count > 1 {
                HStack(spacing: Sp.xs) {
                    ForEach(0..<urls.count, id: \.self) { i in
                        Capsule().fill(.white.opacity(i == page ? 1 : 0.45)).frame(height: 3)
                    }
                }
                .animation(Motion.snappy, value: page)
                .padding(.horizontal, Sp.lg)
                .padding(.top, Sp.sm)
                HStack(spacing: 0) {
                    Color.clear.contentShape(Rectangle()).onTapGesture { turn(to: max(page - 1, 0)) }
                    Color.clear.contentShape(Rectangle()).onTapGesture { turn(to: min(page + 1, urls.count - 1)) }
                        .photosTip(showsTips)
                }
                .onAppear { if showsTips { PhotosTip.cardHasMore = true } }
            }
            VStack(alignment: .leading, spacing: Sp.xs) {
                if card.superLikedMe == true { QTag(label: t("discover.superLikedYou"), tone: .gold, systemImage: "star.fill") }
                if let n = card.sharedSports, n > 0 {
                    QTag(label: n == 1 ? t("discover.sharedOne") : t("discover.sharedMany", ["n": n]), tone: .gold)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Sp.lg)
            .padding(.top, Sp.lg + Sp.xs)
            .allowsHitTesting(false)
        }
        .frame(height: compact ? 380 : 460)
        .clipped()
        .sensoryFeedback(.selection, trigger: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("chat2.photo") + " \(page + 1)/\(max(urls.count, 1))")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: page = min(page + 1, max(urls.count - 1, 0))
            case .decrement: page = max(page - 1, 0)
            @unknown default: break
            }
        }
    }

    private func turn(to new: Int) {
        PhotosTip().invalidate(reason: .actionPerformed)
        guard new != page else { return }
        withAnimation(Motion.fade) { page = new }
    }

    @ViewBuilder private var words: some View {
        if let c = card.nextChallenge, !c.isEmpty {
            section(t("card.nextChallenge"), c)
        }
        if let b = card.bio, !b.isEmpty {
            Text(b).qText(.body).foregroundStyle(Color.q.ink)
        }
        ForEach(card.prompts ?? [], id: \.key) { p in
            section(t("prompts.\(p.key)"), p.answer)
        }
        ForEach(card.achievements ?? [], id: \.title) { a in
            HStack {
                Text(a.title).qText(.callout)
                Spacer()
                if let r = a.result { Text(r).qText(.number) }
            }
            .foregroundStyle(Color.q.ink)
        }
    }

    private func section(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Sp.xs) {
            Text(label).qText(.label).foregroundStyle(Color.q.clayDeep)
            Text(value).qText(.headline).foregroundStyle(Color.q.ink)
        }
        .padding(Sp.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.q.bg, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Someone's whole profile, read top to bottom: photos and words take turns (main photo
/// with the name, sports, a prompt, a photo, goal and about, a prompt, a photo…), so it
/// never turns into a wall of text after the pictures. Tap a photo to look closer.
struct ProfileStoryView: View {
    let card: ProfileCard
    @Environment(SportsCatalog.self) private var catalog
    @State private var viewing: Int?

    private enum Block: Identifiable {
        case photo(Int), sports, prompt(PromptAnswer), about, achievements
        var id: String {
            switch self {
            case .photo(let i): "photo\(i)"
            case .sports: "sports"
            case .prompt(let p): "prompt-\(p.key)"
            case .about: "about"
            case .achievements: "achievements"
            }
        }
    }

    private var blocks: [Block] {
        let photos = Array(card.photoURLs.indices.dropFirst())
        let prompts = card.prompts ?? []
        var words: [Block] = []
        if !(card.sports ?? []).isEmpty { words.append(.sports) }
        if let p = prompts.first { words.append(.prompt(p)) }
        let hasAbout = !(card.nextChallenge ?? "").isEmpty || !(card.bio ?? "").isEmpty
        if hasAbout { words.append(.about) }
        words += prompts.dropFirst().map { .prompt($0) }
        // Two pieces of words, then a photo, while both last; then whatever is left.
        var out: [Block] = [.photo(0)]
        var w = words[...], ph = photos[...]
        while !w.isEmpty || !ph.isEmpty {
            for _ in 0..<2 { if let b = w.popFirst() { out.append(b) } }
            if let i = ph.popFirst() { out.append(.photo(i)) }
        }
        if !(card.achievements ?? []).isEmpty { out.append(.achievements) }
        return out
    }

    var body: some View {
        VStack(spacing: Sp.md) {
            ForEach(blocks) { block in
                switch block {
                case .photo(let i): photo(i)
                case .sports: sports
                case .prompt(let p): prompt(p)
                case .about: about
                case .achievements: achievements
                }
            }
        }
        .fullScreenCover(item: Binding(get: { viewing.map { EditProfileView.PhotoIndex(id: $0) } },
                                       set: { viewing = $0?.id })) { v in
            PhotoViewer(photos: .constant(card.photos), index: v.id, editable: false)
        }
    }

    private func photo(_ i: Int) -> some View {
        let urls = card.photoURLs
        return ZStack(alignment: .bottomLeading) {
            Color.q.blueDeep
            if i < urls.count { QPhoto(url: urls[i]) }
            if i == 0 {
                LinearGradient(colors: [.clear, Color.q.scrim], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: Sp.xxs) {
                    HStack(spacing: Sp.xs) {
                        Text(verbatim: "\(card.name), \(card.age)").qText(.title1).foregroundStyle(.white).lineLimit(2)
                        if card.verified {
                            Image(systemName: "checkmark.seal.fill").font(.q(.headline)).foregroundStyle(.white)
                                .accessibilityLabel(t("card.verified"))
                        }
                    }
                    Text(meta).qText(.callout).foregroundStyle(Color.q.blueMist)
                }
                .padding(Sp.lg)
            }
        }
        .frame(height: i == 0 ? 470 : 440)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { if i < urls.count { viewing = i } }
        .accessibilityElement(children: i == 0 ? .combine : .ignore)
        .accessibilityLabel(i == 0 ? "" : t("chat2.photo") + " \(i + 1)")
        .accessibilityAddTraits(.isButton)
    }

    private var meta: String {
        var parts = [Cities.label(card.travelCity ?? card.city)]
        if let n = card.eventsAttended, n > 0, Config.eventsEnabled { parts.append(t("passport.departures") + " " + String(n)) }
        return parts.joined(separator: " · ")
    }

    private var sports: some View {
        VStack(alignment: .leading, spacing: Sp.sm) {
            FlowLayout(spacing: Sp.xs) {
                ForEach(card.sports ?? [], id: \.code) { s in QTag(label: catalog.label(s.code), tone: .neutral) }
            }
            if let n = card.sharedSports, n > 0 {
                Text(n == 1 ? t("discover.sharedOne") : t("discover.sharedMany", ["n": n]))
                    .qText(.footnote).fontWeight(.bold).foregroundStyle(Color.q.good)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .qCard()
    }

    private func prompt(_ p: PromptAnswer) -> some View {
        VStack(alignment: .leading, spacing: Sp.sm) {
            Text(t("prompts.\(p.key)")).qText(.footnote).fontWeight(.bold).foregroundStyle(Color.q.muted)
            Text(p.answer).qText(.title3).foregroundStyle(Color.q.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .qCard(padding: Sp.lg + Sp.xs)
        .accessibilityElement(children: .combine)
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: Sp.md) {
            if let c = card.nextChallenge, !c.isEmpty {
                VStack(alignment: .leading, spacing: Sp.xxs) {
                    Text(t("card.nextChallenge")).qText(.label).foregroundStyle(Color.q.muted)
                    Text(c).qText(.headline).foregroundStyle(Color.q.ink)
                }
            }
            if let b = card.bio, !b.isEmpty {
                if !(card.nextChallenge ?? "").isEmpty { Divider().overlay(Color.q.line) }
                VStack(alignment: .leading, spacing: Sp.xxs) {
                    Text(t("edit2.about")).qText(.label).foregroundStyle(Color.q.muted)
                    Text(b).qText(.body).foregroundStyle(Color.q.ink)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .qCard()
    }

    private var achievements: some View {
        VStack(alignment: .leading, spacing: Sp.sm) {
            ForEach(card.achievements ?? [], id: \.title) { a in
                HStack {
                    Text(a.title).qText(.callout)
                    Spacer()
                    if let r = a.result { Text(r).qText(.number) }
                }
                .foregroundStyle(Color.q.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .qCard()
    }
}

/// The back of a profile: their passport page, built from the card.
extension PassportPage {
    init(card: ProfileCard) {
        let since = card.memberSince.flatMap { s -> String? in
            let f = DateFormatter(); f.dateFormat = "yyyy-MM"
            return f.date(from: s).map(Fmt.monthYear)
        } ?? ""
        self.init(name: card.name, memberNo: formatMemberNo(card.memberNo), city: Cities.label(card.city), since: since,
                  departures: card.eventsAttended ?? 0, stamps: card.stamps, photo: card.photoURLs.first)
    }
}

/// Full profile: the card, flip to the passport, report / block in the menu.
struct ProfileView: View {
    let id: UUID
    var initial: ProfileCard?
    /// Shown when the profile came from Likes: like / pass at the bottom.
    var onDecide: ((SwipeKind) -> Void)?

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var card: ProfileCard?
    @State private var showPassport = false
    /// The flip's turn in degrees: 0 → 90 (edge on), swap faces, −90 → 0.
    @State private var turn: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reporting = false
    @State private var failed = false

    var body: some View {
        ScrollView {
            if let card {
                VStack(spacing: Sp.lg) {
                    if showPassport {
                        PassportPage(card: card)
                    } else {
                        ProfileStoryView(card: card)
                    }
                }
                .rotation3DEffect(.degrees(turn), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                .padding(Layout.margin)
                .padding(.bottom, onDecide == nil ? 0 : 96)
            } else if failed {
                ErrorStateView(retry: { await load() })
            } else {
                AfterABlink { MarkLoader().padding(.top, Sp.xxl) }
            }
        }
        .background(Color.q.bg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(t("passport.flip")) { flip() }
                .disabled(card == nil)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(t("chat.report"), systemImage: "flag") { reporting = true }
                } label: {
                    Image(systemName: "ellipsis.circle").accessibilityLabel(t("chat.menu"))
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let onDecide {
                HStack(spacing: Sp.lg) {
                    RoundAction(symbol: "xmark", tint: Color.q.clay, size: 64, label: t("common.no")) { onDecide(.pass); dismiss() }
                    RoundAction(symbol: "heart.fill", tint: .white, fill: Color.q.blue, size: 64, label: t("discover.like")) {
                        onDecide(.like); dismiss()
                    }
                }
                .padding(.bottom, Sp.lg)
            }
        }
        .sheet(isPresented: $reporting) {
            if let card { ReportSheet(name: card.name, otherId: card.id) { dismiss() } }
        }
        .task { if card == nil { card = initial; await load() } }
    }

    /// Turns the card edge-on, swaps to the other side, and turns it back face up.
    private func flip() {
        guard !reduceMotion else {
            withAnimation(Motion.fade) { showPassport.toggle() }
            return
        }
        withAnimation(Motion.exit) { turn = 90 } completion: {
            showPassport.toggle()
            turn = -90
            Haptics.bump()
            withAnimation(Motion.hero) { turn = 0 }
        }
    }

    private func load() async {
        failed = false
        do {
            if let fresh = try await Backend.profile(id) { card = fresh } else if card == nil { failed = true }
        } catch {
            if card == nil { failed = true }
        }
    }
}

/// A round floating action (Discover, profile decisions): presses in, and its symbol
/// bounces on every tap.
struct RoundAction: View {
    let symbol: String
    var tint: Color = Color.q.inkSoft
    var fill: Color = Color.q.card
    var size: CGFloat = 48
    let label: String
    let action: () -> Void
    @State private var taps = 0

    var body: some View {
        Button {
            Haptics.bump()
            taps += 1
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: taps)
                .frame(width: size, height: size)
                .background(fill, in: Circle())
                .qElevated()
        }
        .buttonStyle(.qPress)
        .accessibilityLabel(label)
    }
}
