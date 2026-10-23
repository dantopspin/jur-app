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

/// Your sports as chips; the whole row opens the editor.
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
                    Text(catalog.label(s.code)).qText(.caption).lineLimit(1)
                    .foregroundStyle(Color.q.blueText)
                    .padding(.horizontal, Sp.sm)
                    .padding(.vertical, Sp.xs)
                    .background(Color.q.blueTint, in: Capsule())

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
        QList {
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
                        if let waiting = r.pending, waiting > 0 {
                            Text(t("me2.invitePending", ["n": waiting]))
                                .qText(.footnote).foregroundStyle(Color.q.muted)
                        }
                    }
                    SharePassButton(pass: .invite(from: session.profile?.name ?? "", code: code), text: shareText) {
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
                            .lineLimit(1)
                            .fixedSize()
                            .disabled(friendCode.trimmingCharacters(in: .whitespaces).count < 4 || applying)
                    }
                } header: {
                    QSectionHeader(t("me2.friendCode"))
                } footer: {
                    Text(t("me2.friendCodeHint"))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
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
            toasts.show(error)
        }
    }
}

// MARK: help and safety

struct HelpSafetyView: View {
    @Environment(\.openURL) private var openURL
    @State private var datePlans = false

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
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Sp.xl) {
                emergency

                VStack(alignment: .leading, spacing: Sp.sm) {
                    QSectionHeader(t("safety2.before")).padding(.horizontal, Sp.xs)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Sp.sm), GridItem(.flexible(), spacing: Sp.sm)],
                              alignment: .leading, spacing: Sp.sm) {
                        ForEach(tips) { tip in
                            VStack(alignment: .leading, spacing: Sp.sm) {
                                Image(systemName: tip.symbol).font(.q(.title3)).foregroundStyle(Color.q.blueText)
                                    .accessibilityHidden(true)
                                Text(t(tip.key)).qText(.callout).foregroundStyle(Color.q.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                            .qCard(padding: Sp.md)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Sp.sm) {
                    QSectionHeader(t("safety2.tools")).padding(.horizontal, Sp.xs)
                    VStack(spacing: 0) {
                        Button { datePlans = true } label: {
                            row("square.and.arrow.up", t("safety2.sharePlan"), sub: t("safety2.sharePlanSub"))
                        }
                        Divider().overlay(Color.q.line).padding(.leading, Sp.lg + IconSize.toolbar + Sp.md)
                        NavigationLink { BlockedListView() } label: { row("nosign", t("safety2.blocked")) }
                    }
                    .buttonStyle(.plain)
                    .background(Color.q.card, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    // How to report someone (it's on their profile and in the chat).
                    Text(t("me2.tip5")).qText(.footnote).foregroundStyle(Color.q.muted).padding(.horizontal, Sp.xs)
                }

                VStack(alignment: .leading, spacing: Sp.sm) {
                    QSectionHeader(t("me2.contactTitle")).padding(.horizontal, Sp.xs)
                    Button {
                        if let url = URL(string: "mailto:\(Config.supportEmail)") { openURL(url) }
                    } label: { row("envelope", t("me2.writeUs")) }
                    .buttonStyle(.plain)
                    .background(Color.q.card, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    Text(t("safety2.legalNote")).qText(.footnote).foregroundStyle(Color.q.muted).padding(.horizontal, Sp.xs)
                }
            }
            .padding(Layout.margin)
        }
        .background(Color.q.bg)
        .navigationTitle(t("me3.safety"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $datePlans) { DatePlansSheet() }
    }

    /// First and largest: one tap calls 112.
    private var emergency: some View {
        Button {
            if let url = URL(string: "tel://112") { openURL(url) }
        } label: {
            HStack(spacing: Sp.md) {
                Image(systemName: "phone.fill").font(.q(.title3)).foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.q.danger, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Sp.xxs) {
                    Text(t("safety2.call")).qText(.headline).foregroundStyle(Color.q.ink)
                    Text(t("safety2.callSub")).qText(.footnote).foregroundStyle(Color.q.danger)
                }
                Spacer(minLength: 0)
            }
            .padding(Sp.lg)
            .background(Color.q.dangerTint, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.qPressCard)
    }

    private func row(_ symbol: String, _ title: String, sub: String? = nil) -> some View {
        HStack(spacing: Sp.md) {
            Image(systemName: symbol).foregroundStyle(Color.q.blueText).frame(width: IconSize.toolbar)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Sp.xxs) {
                Text(title).qText(.body).foregroundStyle(Color.q.ink)
                if let sub { Text(sub).qText(.footnote).foregroundStyle(Color.q.muted) }
            }
            Spacer(minLength: Sp.sm)
            QChevron()
        }
        .padding(.horizontal, Sp.lg)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

/// Your upcoming accepted dates; each one goes to a friend as a short message.
struct DatePlansSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SportsCatalog.self) private var catalog
    @State private var dates: [UpcomingDate]?

    var body: some View {
        NavigationStack {
            QList {
                if let dates {
                    if dates.isEmpty {
                        Text(t("safety2.noPlans")).qText(.callout).foregroundStyle(Color.q.inkSoft)
                    }
                    ForEach(dates) { d in
                        ShareLink(item: message(d)) {
                            HStack(spacing: Sp.md) {
                                VStack(alignment: .leading, spacing: Sp.xxs) {
                                    Text(d.name).qText(.headline).foregroundStyle(Color.q.ink)
                                    Text(summary(d)).qText(.footnote).foregroundStyle(Color.q.muted)
                                }
                                Spacer(minLength: Sp.sm)
                                Image(systemName: "square.and.arrow.up").foregroundStyle(Color.q.blueText)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(t("safety2.sharePlan"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("common.done")) { dismiss() } } }
            .task { dates = (try? await Backend.upcomingDates()) ?? [] }
        }
        .qSheet()
    }

    private func summary(_ d: UpcomingDate) -> String {
        [d.sport.map { catalog.label($0) }, d.when.flatMap { Date.iso($0) }.map(Fmt.dayTime), d.place]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func message(_ d: UpcomingDate) -> String {
        t("safety2.planText", ["name": d.name, "what": summary(d)])
    }
}

/// People you blocked, with a way to unblock.
struct BlockedListView: View {
    @Environment(ToastCenter.self) private var toasts
    @State private var people: [BlockedPerson]?

    var body: some View {
        QList {
            if let people {
                if people.isEmpty {
                    Text(t("safety2.noBlocked")).qText(.callout).foregroundStyle(Color.q.inkSoft)
                }
                ForEach(people) { p in
                    HStack(spacing: Sp.md) {
                        Avatar(url: p.photo.flatMap(URL.init(string:)), size: 44)
                        Text(p.name).qText(.body).foregroundStyle(Color.q.ink)
                        Spacer(minLength: Sp.sm)
                        Button(t("safety2.unblock")) { Task { await unblock(p) } }
                            .buttonStyle(.q(.secondary, compact: true)).fixedSize()
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(t("safety2.blocked"))
        .navigationBarTitleDisplayMode(.inline)
        .task { people = (try? await Backend.blocked()) ?? [] }
    }

    private func unblock(_ p: BlockedPerson) async {
        let before = people
        withMotion(Motion.smooth) { people?.removeAll { $0.id == p.id } }
        do {
            try await Backend.unblock(p.id)
            toasts.show(t("safety2.unblocked", ["name": p.name]))
        } catch {
            withMotion(Motion.smooth) { people = before }
            toasts.show(error)
        }
    }
}
