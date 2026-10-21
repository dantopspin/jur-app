// Me: your header (opens your passport), profile, verification, Pro and gifts, settings.
import SwiftUI

struct MeView: View {
    @Environment(SessionStore.self) private var session
    @State private var paywall = false
    @State private var proWelcome = false
    @State private var redeeming = false

    var body: some View {
        NavigationStack {
            List {
                if let p = session.profile {
                    NavigationLink { MyPassportView() } label: {
                        HStack(spacing: Sp.lg) {
                            Avatar(url: p.photos.first.flatMap { URL(string: $0) }, size: 72)
                            VStack(alignment: .leading, spacing: Sp.sm) {
                                Text(p.name).qText(.title2).foregroundStyle(Color.q.ink).lineLimit(2)
                                HStack(spacing: Sp.sm) {
                                    QTag(label: formatMemberNo(p.memberNo), tone: .neutral)
                                    if p.verificationStatus == .approved {
                                        QTag(label: t("card.verified"), tone: .blue, systemImage: "checkmark.seal.fill")
                                    }
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: Sp.sm, leading: 0, bottom: Sp.sm, trailing: Sp.md))
                    .accessibilityHint(t("passport.title"))

                    Section {
                        NavigationLink { EditProfileView() } label: { Label(t("me.editProfile"), systemImage: "pencil") }
                        NavigationLink { PromptsEditor() } label: { Label(t("prompts.title"), systemImage: "text.quote") }
                        NavigationLink { TravelView() } label: { Label(t("travel.title"), systemImage: "airplane") }
                        verificationRow(p.verificationStatus)
                    }
                }

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
                                QTag(label: t("me.getPro"), tone: .gold)
                            }
                            Image(systemName: "chevron.right").font(.q(.footnote).weight(.semibold)).foregroundStyle(Color.q.hint)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button { redeeming = true } label: { Label(t("cover.redeemTitle"), systemImage: "gift") }
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
            .refreshable { await session.refreshProfile() }
            .sheet(isPresented: $paywall) { PaywallView() }
            .fullScreenCover(isPresented: $proWelcome) { ProWelcomeView { proWelcome = false } }
            .sheet(isPresented: $redeeming) { RedeemGiftSheet() }
        }
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
}

/// Your own passport page (from get_profile, which includes your stamps).
struct MyPassportView: View {
    @Environment(SessionStore.self) private var session
    @State private var card: ProfileCard?

    var body: some View {
        ScrollView {
            if let card {
                PassportPage(card: card).padding(Layout.margin)
            } else {
                ProgressView().padding(.top, Sp.xxl)
            }
        }
        .background(Color.q.bg)
        .navigationTitle(t("passport.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let id = session.userId { card = try? await Backend.profile(id) }
        }
    }
}

/// A round profile photo with a quiet placeholder while it loads.
struct Avatar: View {
    let url: URL?
    var size: CGFloat = 44

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFill()
            case .failure: Image(systemName: "person.fill").font(.q(.title2)).foregroundStyle(Color.q.hint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.q.line)
            default: Color.q.line
            }
        }
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
