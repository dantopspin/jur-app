// Me: a small hub, like the big dating apps. Your photo with how complete the profile
// is, three round buttons (Settings · Edit · Safety), Pro and your balance, and invites.
// Everything else lives one step in: the editor (with a preview tab) and Settings
// (dating preferences, travel, pause, app, subscription, account).
import SwiftUI
import UIKit

struct MeView: View {
    @Environment(SessionStore.self) private var session
    @State private var paywall = false
    @State private var proWelcome = false
    /// Your own card (for the checklist's prompts item), loaded alongside the profile.
    @State private var card: ProfileCard? = DataCache.get(CacheKey.card, as: ProfileCard?.self) ?? nil
    @State private var opened: ProfileStrength.Kind?
    /// A stamp earned since «Я» was last open: it slams onto your photo.
    @State private var newStamp: StampData?
    @State private var stampLanded = false
    @State private var stampDip = false
    @State private var stampBurst = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Sp.xl) {
                    if let p = session.profile {
                        header(p)
                        actions
                        nextStep(p)
                    }
                    proCard
                    balance
                    NavigationLink { InviteView() } label: { inviteRow }
                        .buttonStyle(.qPressCard)
                }
                .padding(.horizontal, Layout.margin)
                .padding(.top, Sp.sm)
                .padding(.bottom, Sp.xxl)
            }
            .background(Color.q.bg)
            .navigationTitle(t("tabs.me"))
            .toolbarTitleDisplayMode(.inlineLarge)
            .refreshable {
                await session.refreshProfile()
                await session.refreshLimits()
            }
            // Runs on first show and again whenever the profile changes (after an edit).
            .task(id: session.profile) { await loadCard() }
            // Coming back to «Я» from another tab: check again for a new stamp.
            .onAppear { if let card { Task { await landNewStamp(card) } } }
            .navigationDestination(item: $opened) { $0.destination }
            .sheet(isPresented: $paywall) { PaywallView() }
            .fullScreenCover(isPresented: $proWelcome) { ProWelcomeView { proWelcome = false } }
        }
    }

    private var strength: ProfileStrength? {
        guard let p = session.profile else { return nil }
        return ProfileStrength(profile: p, hasPrompts: !(card?.prompts ?? []).isEmpty)
    }

    // MARK: header

    private func header(_ p: MyProfile) -> some View {
        let s = strength
        let share = s.map { Double($0.done) / Double($0.items.count) } ?? 1
        return VStack(spacing: Sp.sm) {
            NavigationLink { MyPassportView() } label: {
                ZStack {
                    Circle().stroke(Color.q.line, lineWidth: 5)
                    Circle().trim(from: 0, to: share)
                        .stroke(Color.q.good, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(Motion.adaptive(Motion.smooth), value: share)
                    Avatar(url: p.photos.first.flatMap { URL(string: $0) }, size: 112)
                }
                .frame(width: 128, height: 128)
                .stampDip(stampDip)
                .overlay(alignment: .bottomTrailing) {
                    if let newStamp {
                        ZStack {
                            DustBurst(trigger: stampBurst)
                            Stamp(data: newStamp)
                                .dynamicTypeSize(.large)
                                .scaleEffect(0.5)
                                .frame(width: 48, height: 48)
                                .stampSlam(stampLanded)
                        }
                        .offset(x: 12, y: 4)
                        .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .bottom) {
                    if share < 1 {
                        Text(verbatim: "\(Int((share * 100).rounded()))%")
                            .qText(.label).foregroundStyle(.white)
                            .padding(.horizontal, Sp.sm).padding(.vertical, Sp.xxs)
                            .background(Color.q.good, in: Capsule())
                            .offset(y: 8)
                    }
                }
            }
            .buttonStyle(.qPress)
            .accessibilityLabel(t("me3.passport"))

            HStack(spacing: Sp.xs) {
                Text(verbatim: age(p).map { "\(p.name), \($0)" } ?? p.name)
                    .qText(.title2).foregroundStyle(Color.q.ink).lineLimit(1)
                if p.verificationStatus == .approved {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.q.blue)
                        .accessibilityLabel(t("card.verified"))
                }
            }
            .padding(.top, Sp.sm)
            if p.paused == true {
                QTag(label: t("me2.paused"), tone: .clay, systemImage: "pause.fill")
            }
            NavigationLink { MyPassportView() } label: {
                Text(verbatim: "\(Cities.label(p.effectiveCity)) · \(t("me3.passport")) ›")
                    .qText(.footnote).foregroundStyle(Color.q.muted)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: the three buttons

    private var actions: some View {
        HStack(alignment: .top, spacing: Sp.xl) {
            NavigationLink { SettingsView() } label: { RoundHubButton(symbol: "gearshape", title: t("me3.settings")) }
            NavigationLink { EditProfileView() } label: { RoundHubButton(symbol: "pencil", title: t("me3.edit"), primary: true) }
            NavigationLink { HelpSafetyView() } label: { RoundHubButton(symbol: "shield", title: t("me3.safety")) }
        }
        .buttonStyle(.qPress)
        .frame(maxWidth: .infinity)
    }

    /// While something is missing: one line with the next thing to do, not a whole checklist.
    @ViewBuilder private func nextStep(_ p: MyProfile) -> some View {
        if let s = strength, card != nil, let next = s.items.first(where: { !$0.done }) {
            Button { opened = next.kind } label: {
                HStack(spacing: Sp.md) {
                    Image(systemName: next.symbol).foregroundStyle(Color.q.blueText).frame(width: 24)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Sp.xxs) {
                        Text(next.title).qText(.callout).foregroundStyle(Color.q.ink)
                        Text(t("me3.complete", ["done": s.done, "all": s.items.count]))
                            .qText(.footnote).foregroundStyle(Color.q.muted)
                    }
                    Spacer(minLength: Sp.sm)
                    QChevron()
                }
                .padding(Sp.lg)
                .background(Color.q.card, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.qPressCard)
            .transition(.opacity)
        }
    }

    // MARK: Pro and balance

    private var proCard: some View {
        Button {
            if session.limits?.pro == true { proWelcome = true } else { paywall = true }
        } label: {
            HStack(spacing: Sp.md) {
                VStack(alignment: .leading, spacing: Sp.xxs) {
                    (Text(verbatim: "JÜR ") + Text(verbatim: "Pro").foregroundStyle(Color.q.gold))
                        .qText(.headline).foregroundStyle(.white)
                    Text(session.limits?.pro == true
                         ? t("me.proActive", ["date": shortDate(session.limits?.proUntil)])
                         : "\(t("paywall.f1")) · \(t("paywall.f2"))")
                        .qText(.footnote).foregroundStyle(Color.q.blueMist)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: Sp.sm)
                if session.limits?.pro != true {
                    Text(t("me3.connect")).qText(.callout).fontWeight(.bold)
                        .foregroundStyle(Color.q.onGold)
                        .padding(.horizontal, Sp.md).padding(.vertical, Sp.sm)
                        .background(Color.q.gold, in: Capsule())
                        .fixedSize()
                } else {
                    Image(systemName: "chevron.right").font(.q(.footnote).weight(.semibold)).foregroundStyle(Color.q.blueMist)
                }
            }
            .padding(Sp.lg)
            .background(Color.q.blueNight, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.qPressCard)
    }

    @ViewBuilder private var balance: some View {
        if let l = session.limits {
            VStack(spacing: Sp.xs) {
                HStack(spacing: Sp.sm) {
                    tile(symbol: "heart.fill", tint: Color.q.blue, value: l.likesLeft.map(String.init) ?? "∞", label: t("me3.likes"))
                    tile(symbol: "star.fill", tint: Color.q.gold, value: "\(l.supersLeft)", label: t("me3.supers"))
                    tile(symbol: "bolt.fill", tint: Color.q.blueText,
                         value: "\(l.boostCredits + (l.freeBoostAvailable ? 1 : 0))", label: t("me3.boosts"))
                }
                Text(t("me2.balanceFooter")).qText(.caption).foregroundStyle(Color.q.muted)
            }
        }
    }

    private func tile(symbol: String, tint: Color, value: String, label: String) -> some View {
        VStack(spacing: Sp.xxs) {
            Image(systemName: symbol).foregroundStyle(tint).accessibilityHidden(true)
            Text(verbatim: value).qText(.number).foregroundStyle(Color.q.ink)
                .contentTransition(.numericText())
            Text(label).qText(.caption).foregroundStyle(Color.q.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Sp.md)
        .background(Color.q.card, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var inviteRow: some View {
        HStack(spacing: Sp.md) {
            Image(systemName: "gift").foregroundStyle(Color.q.blueText).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Sp.xxs) {
                Text(t("me2.invite")).qText(.callout).foregroundStyle(Color.q.ink)
                Text(t("me3.inviteSub")).qText(.footnote).foregroundStyle(Color.q.muted)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: Sp.sm)
            QChevron()
        }
        .padding(Sp.lg)
        .background(Color.q.card, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .contentShape(Rectangle())
    }

    // MARK: loading

    private func loadCard() async {
        guard let id = session.userId, let c = try? await Backend.myCard(id) else { return }
        withMotion(Motion.fade) { card = c }
        await landNewStamp(c)
    }

    /// The newest stamp you haven't seen yet drops onto your photo, with the thump and the
    /// dust of every stamp landing. Each one lands once.
    private func landNewStamp(_ c: ProfileCard) async {
        guard let id = session.userId, newStamp == nil,
              let fresh = StampLedger.unseen(c.stamps, owner: id).last else { return }
        StampLedger.markSeen(c.stamps, owner: id)
        newStamp = fresh
        stampLanded = false
        try? await Task.sleep(for: .milliseconds(500))
        await StampMoment.play(land: { stampLanded = true }, dip: { stampDip = $0 }, dust: { stampBurst += 1 })
        UIAccessibility.post(notification: .announcement, argument: t("me3.newStamp", ["stamp": fresh.kind.label]))
    }

    private func age(_ p: MyProfile) -> Int? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: String(p.birthdate.prefix(10))) else { return nil }
        return Calendar.current.dateComponents([.year], from: d, to: .now).year
    }
}

/// One of the three round buttons under your photo; the middle one (Edit) is bigger and blue.
struct RoundHubButton: View {
    let symbol: String
    let title: String
    var primary = false

    var body: some View {
        VStack(spacing: Sp.sm) {
            Image(systemName: symbol)
                .font(.system(size: (primary ? 64 : 56) * 0.38, weight: .bold))
                .foregroundStyle(primary ? .white : Color.q.inkSoft)
                .frame(width: primary ? 64 : 56, height: primary ? 64 : 56)
                .background(primary ? Color.q.blue : Color.q.card, in: Circle())
                .qElevated()
            Text(title).qText(.caption).fontWeight(primary ? .bold : .semibold).foregroundStyle(Color.q.ink)
        }
        .padding(.top, primary ? 0 : Sp.md)
        .frame(minWidth: 72)
        .contentShape(Rectangle())
    }
}

/// Your own passport page (from get_profile, which includes your stamps).
struct MyPassportView: View {
    @Environment(SessionStore.self) private var session
    @State private var card: ProfileCard? = DataCache.get(CacheKey.card, as: ProfileCard?.self) ?? nil

    var body: some View {
        ScrollView {
            if let card {
                PassportPage(card: card).padding(Layout.margin)
            } else {
                AfterABlink { MarkLoader().padding(.top, Sp.xxl) }
            }
        }
        .background(Color.q.bg)
        .navigationTitle(t("passport.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let id = session.userId, let fresh = try? await Backend.myCard(id) { card = fresh }
        }
    }
}

/// A round profile photo with a quiet placeholder while it loads.
struct Avatar: View {
    let url: URL?
    var size: CGFloat = 44

    var body: some View {
        QPhoto(url: url, size: size > 140 ? .full : .thumb)
            .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// "21 October 2026" in the app's language, Almaty time.
func shortDate(_ iso: String?) -> String {
    guard let iso, let d = ISO8601DateFormatter.flexible(iso) else { return "" }
    let f = DateFormatter()
    f.locale = L10n.current.locale
    f.timeZone = TimeZone(identifier: "Asia/Almaty")
    f.dateStyle = .long
    return f.string(from: d)
}

extension ISO8601DateFormatter {
    /// Parses Postgres timestamps with or without fractional seconds.
    static func flexible(_ s: String) -> Date? {
        let a = ISO8601DateFormatter()
        a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = a.date(from: s) { return d }
        a.formatOptions = [.withInternetDateTime]
        return a.date(from: s)
    }
}

/// Which stamps you've already seen land, per account. A stamp counts as new when its
/// kind or its small line changes ("×5" becoming "×6" is a new one). The very first time,
/// everything you already have counts as seen, so nothing old drops in.
enum StampLedger {
    private static func key(_ owner: UUID) -> String { "jur.stampsSeen.\(owner.uuidString)" }
    private static func token(_ s: StampData) -> String { "\(s.kind.rawValue)|\(s.detail ?? "")" }

    static func unseen(_ stamps: [StampData], owner: UUID) -> [StampData] {
        guard let seen = UserDefaults.standard.stringArray(forKey: key(owner)) else {
            markSeen(stamps, owner: owner)
            return []
        }
        let set = Set(seen)
        return stamps.filter { !set.contains(token($0)) }
    }

    static func markSeen(_ stamps: [StampData], owner: UUID) {
        let old = UserDefaults.standard.stringArray(forKey: key(owner)) ?? []
        let all = Set(old).union(stamps.map(token))
        UserDefaults.standard.set(Array(all), forKey: key(owner))
    }
}
