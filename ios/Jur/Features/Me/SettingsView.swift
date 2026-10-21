// Settings (milestone 1): language, legal, support, sign out, delete account.
import SwiftUI

struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.openURL) private var openURL
    @AppStorage(L10n.storageKey) private var language: String = AppLanguage.device.rawValue
    @State private var confirmDelete = false
    @State private var deleting = false

    var body: some View {
        List {
            Section {
                Picker(t("settings.language"), selection: Binding(
                    get: { AppLanguage(rawValue: language) ?? .ru },
                    set: { new in
                        L10n.current = new
                        language = new.rawValue
                        if let id = session.userId { Task { try? await Backend.updateLocale(new, userId: id) } }
                    })) {
                    ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(Color.q.inkSoft)
            }

            Section {
                SettingsLink(symbol: "lock", title: t("settings.privacy")) { openURL(Config.privacyURL) }
                SettingsLink(symbol: "doc.text", title: t("settings.terms")) { openURL(Config.termsURL) }
                SettingsLink(symbol: "questionmark.circle", title: t("settings.support")) {
                    if let url = URL(string: "mailto:\(Config.supportEmail)") { openURL(url) }
                }
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
    }

    private static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    private static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }

    private func deleteAccount() async {
        deleting = true
        defer { deleting = false }
        do {
            try await Backend.deleteAccount()
            toasts.show(t("settings.deleted"))
            await session.signOut()
        } catch {
            toasts.show(t("common.error"), error: true)
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
