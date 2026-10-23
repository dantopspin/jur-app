// Me: your header (opens your passport, shows your latest stamps), how others see you,
// what's left to fill in, your sports, what you're looking for, Pro and your balance,
// invites, help and safety, and pausing.
import SwiftUI

struct MeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @State private var paywall = false
    @State private var proWelcome = false
    @State private var redeeming = false
    @State private var previewing = false

    /// Your own card (stamps, prompts) and sports, loaded alongside the profile.
    @State private var card: ProfileCard? = DataCache.get(CacheKey.card, as: ProfileCard?.self) ?? nil
    @State private var sports: [String: Level] = [:]
    /// Local copies so the controls answer at once; saved, then the profile refreshes.
    @State private var mode: ProfileMode = .dating
    @State private var buddyWith: InterestedIn = .everyone
    @State private var paused = false
    @State private var saving = false
    @State private var opened: ProfileStrength.Kind?

    var body: some View {
        NavigationStack {
            List {
                if let p = session.profile {
                    header(p)
                    previewRow
                    strength(p)

                    Section {
                        NavigationLink { EditProfileView() } label: { Label(t("me.editProfile"), systemImage: "pencil") }
                        NavigationLink { PromptsEditor() } label: { Label(t("prompts.title"), systemImage: "text.quote") }
                        NavigationLink { TravelView() } label: { Label(t("travel.title"), systemImage: "airplane") }
                        verificationRow(p.verificationStatus)
                    }

                    Section(t("me2.sports")) {
                        NavigationLink { EditProfileView() } label: { SportsGlance(sports: sports) }
                            .accessibilityHint(t("me2.edit"))
                    }

                    lookingFor
                }

                proAndBalance

                Section {
                    NavigationLink { InviteView() } label: { Label(t("me2.invite"), systemImage: "gift") }
                    NavigationLink { HelpSafetyView() } label: { Label(t("me2.help"), systemImage: "shield") }
                }

                if session.profile != nil {
                    Section {
                        Toggle(isOn: Binding(get: { paused }, set: { new in Task { await setPaused(new) } })) {
                            Label(t("me2.pause"), systemImage: "pause.circle")
                        }
                        .disabled(saving)
                    } footer: {
                        Text(t("me2.pauseFooter")).qText(.footnote).foregroundStyle(Color.q.muted)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.q.bg)
            .navigationTitle(t("tabs.me"))
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsView() } label: {
                        Image(systemName: "gearshape").accessibilityLabel(t("me.settings"))
                    }
                }
            }
            .refreshable {
                await session.refreshProfile()
                await session.refreshLimits()
            }
            // Runs on first show and again whenever the profile changes (after an edit).
            .task(id: session.profile) { await loadExtras() }
            .navigationDestination(item: $opened) { $0.destination }
            .sheet(isPresented: $paywall) { PaywallView() }
            .sheet(isPresented: $previewing) {
                if let card { ProfilePreviewSheet(card: card) }
            }
            .fullScreenCover(isPresented: $proWelcome) { ProWelcomeView { proWelcome = false } }
            .sheet(isPresented: $redeeming) { RedeemGiftSheet() }
        }
    }

    // MARK: sections

    private func header(_ p: MyProfile) -> some View {
        NavigationLink { MyPassportView() } label: {
            HStack(spacing: Sp.lg) {
                Avatar(url: p.photos.first.flatMap { URL(string: $0) }, size: 72)
                VStack(alignment: .leading, spacing: Sp.sm) {
                    Text(p.name).qText(.title2).foregroundStyle(Color.q.ink).lineLimit(2)
                    FlowLayout(spacing: Sp.xs) {
                        QTag(label: formatMemberNo(p.memberNo), tone: .neutral)
                        if p.verificationStatus == .approved {
                            QTag(label: t("card.verified"), tone: .blue, systemImage: "checkmark.seal.fill")
                        }
                        if paused {
                            QTag(label: t("me2.paused"), tone: .clay, systemImage: "pause.fill")
                        }
                    }
                    if let card {
                        StampStrip(stamps: card.stamps)
                            .transition(.opacity)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: Sp.sm, leading: 0, bottom: Sp.sm, trailing: Sp.md))
        .accessibilityHint(t("passport.title"))
    }

    private var previewRow: some View {
        Button { previewing = true } label: {
            Label(t("me2.preview"), systemImage: "eye")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.q(.secondary))
        .disabled(card == nil)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: Sp.sm, trailing: 0))
    }

    /// The checklist, only while something is left to do.
    @ViewBuilder private func strength(_ p: MyProfile) -> some View {
        if let card {
            let s = ProfileStrength(profile: p, hasPrompts: !(card.prompts ?? []).isEmpty)
            if !s.complete {
                ProfileStrengthCard(strength: s) { opened = $0 }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: Sp.sm, leading: 0, bottom: Sp.sm, trailing: 0))
            }
        }
    }

    private var lookingFor: some View {
        Section {
            Picker(t("mode.title"), selection: Binding(get: { mode }, set: { new in Task { await setMode(new) } })) {
                Text(t("mode.dating")).tag(ProfileMode.dating)
                Text(t("mode.buddy")).tag(ProfileMode.buddy)
                Text(t("mode.both")).tag(ProfileMode.both)
            }
            if mode != .dating {
                Picker(t("mode.buddyWith"), selection: Binding(get: { buddyWith }, set: { new in Task { await setBuddyWith(new) } })) {
                    Text(t("onboarding.women")).tag(InterestedIn.women)
                    Text(t("onboarding.men")).tag(InterestedIn.men)
                    Text(t("onboarding.everyone")).tag(InterestedIn.everyone)
                }
            }
        } footer: {
            if mode != .dating {
                Text(t("mode.buddyHint")).qText(.footnote).foregroundStyle(Color.q.muted)
            }
        }
        .pickerStyle(.menu)
        .tint(Color.q.inkSoft)
        .disabled(saving)
    }

    private var proAndBalance: some View {
        Section {
            Button {
                if session.limits?.pro == true { proWelcome = true } else { paywall = true }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: Sp.xxs) {
                        Text(t("me.pro")).qText(.headline).foregroundStyle(Color.q.ink)
                        if let l = session.limits {
                            Text(l.pro ? t("me.proActive", ["date": shortDate(l.proUntil)]) : "\(t("paywall.f1")) · \(t("paywall.f2"))")
                                .qText(.footnote).foregroundStyle(Color.q.muted)
                        }
                    }
                    Spacer()
                    if session.limits?.pro != true {
                        QTag(label: t("me.getPro"), tone: .gold).fixedSize()
                    }
                    Image(systemName: "chevron.right").font(.q(.footnote).weight(.semibold)).foregroundStyle(Color.q.hint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let l = session.limits {
                balanceRow(t("me2.likesToday"), symbol: "heart",
                           value: l.likesLeft.map(String.init) ?? t("me2.unlimited"))
                balanceRow(t("me2.supersToday"), symbol: "star", value: "\(l.supersLeft)")
                balanceRow(t("me2.boosts"), symbol: "bolt",
                           value: "\(l.boostCredits + (l.freeBoostAvailable ? 1 : 0))")
            }
            Button { redeeming = true } label: { Label(t("cover.redeemTitle"), systemImage: "gift") }
        } footer: {
            if session.limits != nil {
                Text(t("me2.balanceFooter")).qText(.footnote).foregroundStyle(Color.q.muted)
            }
        }
    }

    private func balanceRow(_ title: String, symbol: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: symbol).foregroundStyle(Color.q.ink)
            Spacer()
            Text(value).qText(.number).foregroundStyle(Color.q.blueText)
                .contentTransition(.numericText())
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func verificationRow(_ status: Verification) -> some View {
        switch status {
        case .approved:
            Label(t("me.verified"), systemImage: "checkmark.seal.fill").foregroundStyle(Color.q.blueText)
        case .pending:
            Label(t("me.verifyPending"), systemImage: "clock").foregroundStyle(Color.q.muted)
        case .rejected:
            NavigationLink { VerifyView() } label: { Label(t("me.verifyRejected"), systemImage: "exclamationmark.triangle") }
        case .unverified:
            NavigationLink { VerifyView() } label: { Label(t("me.verify"), systemImage: "checkmark.seal") }
        }
    }

    // MARK: loading and saving

    private func loadExtras() async {
        guard let p = session.profile, let id = session.userId else { return }
        if !saving {
            mode = p.mode ?? .dating
            buddyWith = p.buddyWith ?? .everyone
            paused = p.paused ?? false
        }
        async let s = try? Backend.mySports(userId: id)
        let c = try? await Backend.myCard(id)
        let loadedSports = await s
        withMotion(Motion.fade) {
            if let c { card = c }
            if let loadedSports { sports = loadedSports }
        }
    }

    private func setMode(_ new: ProfileMode) async {
        guard let id = session.userId, new != mode else { return }
        let old = mode
        withMotion(Motion.smooth) { mode = new }
        await save(revert: { mode = old }) { try await Backend.setMode(userId: id, new) }
    }

    private func setBuddyWith(_ new: InterestedIn) async {
        guard let id = session.userId, new != buddyWith else { return }
        let old = buddyWith
        buddyWith = new
        await save(revert: { buddyWith = old }) { try await Backend.setBuddyWith(userId: id, new) }
    }

    private func setPaused(_ new: Bool) async {
        guard new != paused else { return }
        paused = new
        let ok = await save(revert: { paused = !new }) { try await Backend.setPaused(new) }
        if ok { toasts.show(t(new ? "me2.paused" : "me2.resumed"), symbol: new ? "pause.circle.fill" : "eye.fill") }
    }

    /// Saves, then refreshes the profile; on failure puts the control back and says so.
    @discardableResult
    private func save(revert: () -> Void, _ op: () async throws -> Void) async -> Bool {
        saving = true
        defer { saving = false }
        do {
            try await op()
            Haptics.tick()
            await session.refreshProfile()
            return true
        } catch {
            revert()
            toasts.show(error)
            return false
        }
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
