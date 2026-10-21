// Me (milestone 1): who you are, Pro status, and Settings. The full profile card,
// prompts, badges and invites come in milestone 2.
import SwiftUI

struct MeView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        NavigationStack {
            List {
                if let p = session.profile {
                    // The header sits on the ground, not inside a row. The Passport opens from here in milestone 2.
                    HStack(spacing: Sp.lg) {
                        Avatar(url: p.photos.first.flatMap { URL(string: $0) }, size: 72)
                        VStack(alignment: .leading, spacing: Sp.sm) {
                            Text(p.name).qText(.title2).foregroundStyle(Color.q.ink).lineLimit(2)
                            HStack(spacing: Sp.sm) {
                                QTag(label: memberNo(p.memberNo), tone: .neutral)
                                if p.verificationStatus == .approved {
                                    QTag(label: t("card.verified"), tone: .blue, systemImage: "checkmark.seal.fill")
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: Sp.sm, leading: 0, bottom: Sp.sm, trailing: 0))
                    .accessibilityElement(children: .combine)
                }
                // Plain text until the paywall exists (milestone 2); then this row becomes a
                // NavigationLink with a chevron.
                Section {
                    VStack(alignment: .leading, spacing: Sp.xxs) {
                        Text(t("me.pro")).qText(.headline).foregroundStyle(Color.q.ink)
                        if let l = session.limits {
                            Text(l.pro ? t("me.proActive", ["date": shortDate(l.proUntil)]) : "\(t("paywall.f1")) · \(t("paywall.f2"))")
                                .qText(.footnote).foregroundStyle(Color.q.muted)
                        }
                    }
                    .padding(.vertical, Sp.xxs)
                    .accessibilityElement(children: .combine)
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
