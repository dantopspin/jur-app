// Settings: who you meet (looking for, who to show, city, travel, pause), the app
// (notifications, sounds, photo blur, language), the subscription, support and legal,
// and the account.
import RevenueCat
import StoreKit
import SwiftUI

struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.openURL) private var openURL
    @AppStorage(L10n.storageKey) private var language: String = AppLanguage.device.rawValue
    @AppStorage(ChatMedia.blurKey) private var blurPhotos = true
    @AppStorage(Sounds.enabledKey) private var sounds = true
    @State private var confirmDelete = false
    @State private var deleting = false
    /// Local copies so the controls answer at once; saved, then the profile refreshes.
    @State private var mode: ProfileMode = .dating
    @State private var buddyWith: InterestedIn = .everyone
    @State private var paused = false
    @State private var city = "almaty"
    @State private var saving = false
    @State private var filters = false
    @State private var manageSubscription = false
    @State private var redeeming = false
    @State private var restoring = false

    var body: some View {
        List {
            dating
            app
            subscription

            Section(t("settings2.support")) {
                SettingsLink(symbol: "questionmark.circle", title: t("settings.support")) {
                    if let url = URL(string: "mailto:\(Config.supportEmail)") { openURL(url) }
                }
                SettingsLink(symbol: "doc.text", title: t("settings.terms")) { openURL(Config.termsURL) }
                SettingsLink(symbol: "lock", title: t("settings.privacy")) { openURL(Config.privacyURL) }
            }
            Section {
                Button(t("settings.signOut")) { Task { await session.signOut() } }
                    .frame(maxWidth: .infinity)
            }
            Section {
                Button(role: .destructive) { confirmDelete = true } label: {
                    HStack { Spacer(); if deleting { ProgressView() } else { Text(t("settings.deleteAccount")) }; Spacer() }
                }
                .disabled(deleting)
            } footer: {
                Text(t("settings.version", ["v": Self.version, "b": Self.build]))
                    .qText(.caption).foregroundStyle(Color.q.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Sp.lg)
            }
        }
        .navigationTitle(t("settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color.q.bg)
        .confirmationDialog(t("settings.deleteAccount"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(t("common.delete"), role: .destructive) { Task { await deleteAccount() } }
            Button(t("common.cancel"), role: .cancel) {}
        } message: {
            Text(t("settings.deleteConfirm"))
        }
        .sheet(isPresented: $filters) { FiltersSheet {} }
        .sheet(isPresented: $redeeming) { RedeemGiftSheet() }
        .manageSubscriptionsSheet(isPresented: $manageSubscription)
        .task(id: session.profile) { syncFromProfile() }
    }

    // MARK: who you meet

    private var dating: some View {
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
            Button { filters = true } label: {
                valueRow(t("filters.title"), value: whoToShow)
            }
            .buttonStyle(.plain)
            Picker(t("onboarding.cityTitle"), selection: Binding(get: { city }, set: { new in Task { await setCity(new) } })) {
                ForEach(Cities.all, id: \.self) { Text(Cities.label($0)).tag($0) }
            }
            NavigationLink { TravelView() } label: {
                HStack {
                    Text(t("travel.title")).foregroundStyle(Color.q.ink)
                    if session.limits?.pro != true { QTag(label: "PRO", tone: .gold) }
                    Spacer()
                    Text(travelValue).foregroundStyle(Color.q.muted)
                }
            }
            Toggle(t("me2.pause"), isOn: Binding(get: { paused }, set: { new in Task { await setPaused(new) } }))
                .tint(Color.q.good)
        } header: {
            Text(t("settings2.dating"))
        } footer: {
            Text(mode != .dating ? t("mode.buddyHint") + " " + t("me2.pauseFooter") : t("me2.pauseFooter"))
                .qText(.footnote).foregroundStyle(Color.q.muted)
        }
        .pickerStyle(.menu)
        .tint(Color.q.inkSoft)
        .disabled(saving)
    }

    private var whoToShow: String {
        guard let p = session.profile else { return "" }
        let who = switch p.interestedIn {
        case .women: t("onboarding.women")
        case .men: t("onboarding.men")
        case .everyone: t("onboarding.everyone")
        }
        return "\(who), \(p.ageMin ?? 18)–\(p.ageMax ?? 60)"
    }

    private var travelValue: String {
        guard let p = session.profile, let c = p.travelCity,
              let until = p.travelUntil.flatMap({ Date.iso($0) }), until > .now else { return t("settings2.off") }
        return Cities.label(c)
    }

    // MARK: the app

    private var app: some View {
        Section {
            SettingsLink(symbol: "bell", title: t("settings2.notifications")) {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            }
            Toggle(isOn: $sounds) { Label(t("settings.sounds"), systemImage: "speaker.wave.2") }
                .tint(Color.q.good)
            Toggle(isOn: $blurPhotos) { Label(t("safety.blurSetting"), systemImage: "eye.slash") }
                .tint(Color.q.good)
            Picker(selection: Binding(
                get: { AppLanguage(rawValue: language) ?? .ru },
                set: { new in
                    L10n.current = new
                    language = new.rawValue
                    if let id = session.userId { Task { try? await Backend.updateLocale(new, userId: id) } }
                })) {
                ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0) }
            } label: { Label(t("settings.language"), systemImage: "globe") }
            .pickerStyle(.menu)
            .tint(Color.q.inkSoft)
        } header: {
            Text(t("settings2.app"))
        } footer: {
            Text(t("safety.footer") + " " + t("safety.footerDevice")).qText(.footnote).foregroundStyle(Color.q.muted)
        }
    }

    // MARK: subscription

    private var subscription: some View {
        Section(t("settings2.subscription")) {
            SettingsLink(symbol: "creditcard", title: t("settings.manageSub")) { manageSubscription = true }
            SettingsLink(symbol: "arrow.clockwise", title: t("paywall.restore")) { Task { await restore() } }
                .disabled(restoring)
            SettingsLink(symbol: "gift", title: t("cover.redeemTitle")) { redeeming = true }
        }
    }

    private func valueRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Color.q.ink)
            Spacer()
            Text(value).foregroundStyle(Color.q.muted).lineLimit(1)
            Image(systemName: "chevron.right").font(.q(.footnote).weight(.semibold)).foregroundStyle(Color.q.hint)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    private static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    private static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }

    // MARK: saving

    private func syncFromProfile() {
        guard let p = session.profile, !saving else { return }
        mode = p.mode ?? .dating
        buddyWith = p.buddyWith ?? .everyone
        paused = p.paused ?? false
        city = p.city
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

    private func setCity(_ new: String) async {
        guard let id = session.userId, new != city else { return }
        let old = city
        city = new
        await save(revert: { city = old }) { try await Backend.setCity(userId: id, new) }
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

    private func restore() async {
        restoring = true
        defer { restoring = false }
        do {
            _ = try await Purchases.shared.restorePurchases()
            await session.refreshLimits()
            toasts.show(t("paywall.restored"))
        } catch { toasts.show(error) }
    }

    private func deleteAccount() async {
        deleting = true
        defer { deleting = false }
        do {
            try await Backend.deleteAccount()
            toasts.show(t("settings.deleted"))
            await session.signOut()
        } catch {
            toasts.show(error)
        }
    }
}

/// A Settings row that opens something outside the app: symbol, title, chevron.
struct SettingsLink: View {
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: symbol)
                    .qText(.body)
                    .foregroundStyle(Color.q.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.q(.footnote).weight(.semibold))
                    .foregroundStyle(Color.q.hint)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
