// Pieces of the Me tab: your stamps at a glance, your card as others see it, your sports,
// inviting friends, and help and safety.
import SwiftUI

// MARK: stamps

/// The latest few stamps, small, with "+N" for the rest. There is one stamp per kind
/// (repeats count up on the stamp itself), so the passport stays short; the strip only
/// keeps the header tidy if more kinds are added later.
struct StampStrip: View {
    let stamps: [StampData]
    var shown = 3

    var body: some View {
        HStack(spacing: Sp.xs) {
            if stamps.isEmpty {
                Text(t("me2.noStamps")).qText(.caption).foregroundStyle(Color.q.muted)
            } else {
                ForEach(stamps.suffix(shown)) { s in
                    Stamp(data: s)
                        .dynamicTypeSize(.large)
                        .scaleEffect(0.42)
                        .frame(width: 40, height: 40)
                }
                if stamps.count > shown {
                    Text("+\(stamps.count - shown)").qText(.caption).foregroundStyle(Color.q.muted)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stamps.isEmpty ? t("me2.noStamps") : t("me2.stamps", ["n": stamps.count]))
    }
}

// MARK: preview

/// Your own card exactly as Discover shows it to others.
struct ProfilePreviewSheet: View {
    let card: ProfileCard
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Sp.md) {
                    Text(t("me2.previewNote")).qText(.footnote).foregroundStyle(Color.q.muted)
                    ProfileCardView(card: card)
                }
                .padding(Layout.margin)
            }
            .background(Color.q.bg)
            .navigationTitle(t("me2.preview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(t("common.done")) { dismiss() } }
            }
        }
    }
}

// MARK: sports

/// Your sports and levels as chips; the whole row opens the editor.
struct SportsGlance: View {
    let sports: [String: Level]
    @Environment(SportsCatalog.self) private var catalog

    private struct Pick: Identifiable {
        let code: String
        let level: Level
        var id: String { code }
    }

    private var ordered: [Pick] {
        sports.map { Pick(code: $0.key, level: $0.value) }
            .sorted { (catalog.sport($0.code)?.sort ?? 999) < (catalog.sport($1.code)?.sort ?? 999) }
    }

    var body: some View {
        if sports.isEmpty {
            Label(t("me2.sportsEmpty"), systemImage: "plus.circle").foregroundStyle(Color.q.blueText)
        } else {
            FlowLayout(spacing: Sp.xs) {
                ForEach(ordered) { s in
                    HStack(spacing: Sp.xs) {
                        Text(catalog.label(s.code)).qText(.caption).lineLimit(1)
                        HStack(spacing: 2) {
                            ForEach(0..<4, id: \.self) { i in
                                Circle()
                                    .fill(Color.q.blueText.opacity(i < s.level.pips ? 1 : 0.25))
                                    .frame(width: 4, height: 4)
                            }
                        }
                    }
                    .foregroundStyle(Color.q.blueText)
                    .padding(.horizontal, Sp.sm)
                    .padding(.vertical, Sp.xs)
                    .background(Color.q.blueTint, in: Capsule())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(catalog.label(s.code) + ", " + t("levels.\(s.level.rawValue)"))
                }
            }
            .padding(.vertical, Sp.xxs)
        }
    }
}

// MARK: invite

struct InviteView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @State private var referrals: Referrals?
    @State private var friendCode = ""
    @State private var applying = false

    private var code: String { session.profile?.referralCode ?? "" }

    /// A friend's code can be entered once, in the first 7 days.
    private var canEnterFriendCode: Bool {
        guard let p = session.profile, p.referredBy == nil else { return false }
        guard let created = p.createdAt.flatMap({ Date.iso($0) }) else { return true }
        return created > .now.addingTimeInterval(-7 * 24 * 3600)
    }

    private var shareText: String {
        t("me2.shareText", ["code": code, "url": Config.appStoreURL.absoluteString])
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Sp.md) {
                    Text(t("me2.inviteLead", ["every": referrals?.every ?? 2, "days": referrals?.bonusDays ?? 7]))
                        .qText(.callout).foregroundStyle(Color.q.inkSoft)
                    Text(t("me2.yourCode")).qText(.label).foregroundStyle(Color.q.muted)
                    HStack {
                        Text(code).qText(.display).foregroundStyle(Color.q.ink)
                            .textSelection(.enabled)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = code
                            Haptics.tick()
                            toasts.show(t("me2.copied"))
                        } label: {
                            Image(systemName: "doc.on.doc").accessibilityLabel(t("me2.copy"))
                        }
                        .buttonStyle(.borderless)
                    }
                    if let r = referrals {
                        Text(t("me2.inviteProgress", ["n": r.count, "left": r.toNext, "days": r.bonusDays]))
                            .qText(.footnote).foregroundStyle(Color.q.blueText)
                    }
                    ShareLink(item: shareText) {
                        Label(t("me2.share"), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.q(.primary))
                }
                .padding(.vertical, Sp.sm)
            }

            if canEnterFriendCode {
                Section {
                    HStack {
                        TextField(t("me2.code"), text: $friendCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit { Task { await apply() } }
                        Button(t("me2.apply")) { Task { await apply() } }
                            .disabled(friendCode.trimmingCharacters(in: .whitespaces).count < 4 || applying)
                    }
                } header: {
                    Text(t("me2.friendCode"))
                } footer: {
                    Text(t("me2.friendCodeHint"))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.q.bg)
        .navigationTitle(t("me2.invite"))
        .navigationBarTitleDisplayMode(.inline)
        .task { referrals = try? await Backend.referrals() }
    }

    private func apply() async {
        let entered = friendCode.trimmingCharacters(in: .whitespaces)
        guard entered.count >= 4, !applying else { return }
        applying = true
        defer { applying = false }
        do {
            let r = try await Backend.redeemReferral(entered)
            if r.ok {
                Haptics.success()
                toasts.show(t("me2.friendCodeOk"))
                friendCode = ""
                await session.refreshProfile()
            } else {
                let key = "me2.err_\(r.error ?? "")"
                toasts.show(t(key) == key ? t("common.error") : t(key), error: true)
            }
        } catch {
            toasts.show(t("common.error"), error: true)
        }
    }
}

// MARK: help and safety

struct HelpSafetyView: View {
    @Environment(\.openURL) private var openURL

    private struct Tip: Identifiable {
        let symbol: String
        let key: String
        var id: String { key }
    }

    private let tips = [
        Tip(symbol: "person.3", key: "me2.tip1"),
        Tip(symbol: "location", key: "me2.tip2"),
        Tip(symbol: "bubble.left.and.bubble.right", key: "me2.tip3"),
        Tip(symbol: "banknote", key: "me2.tip4"),
        Tip(symbol: "flag", key: "me2.tip5"),
    ]

    var body: some View {
        List {
            Section(t("me2.tipsTitle")) {
                ForEach(tips) { tip in
                    Label {
                        Text(t(tip.key)).qText(.callout).foregroundStyle(Color.q.ink)
                    } icon: {
                        Image(systemName: tip.symbol).foregroundStyle(Color.q.blueText)
                    }
                    .padding(.vertical, Sp.xxs)
                }
            }

            Section {
                SettingsLink(symbol: "envelope", title: t("me2.writeUs")) {
                    if let url = URL(string: "mailto:\(Config.supportEmail)") { openURL(url) }
                }
                SettingsLink(symbol: "questionmark.circle", title: t("settings.support")) { openURL(Config.supportURL) }
            } header: {
                Text(t("me2.contactTitle"))
            } footer: {
                Text(t("me2.emergency")).qText(.footnote).fontWeight(.semibold).foregroundStyle(Color.q.clay)
            }

            Section(t("me2.legalTitle")) {
                SettingsLink(symbol: "lock", title: t("settings.privacy")) { openURL(Config.privacyURL) }
                SettingsLink(symbol: "doc.text", title: t("settings.terms")) { openURL(Config.termsURL) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.q.bg)
        .navigationTitle(t("me2.help"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
