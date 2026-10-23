import SwiftUI

@main
struct JurApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = SessionStore()
    @State private var toasts = ToastCenter()
    @State private var sports = SportsCatalog()
    @AppStorage(L10n.storageKey) private var language: String = AppLanguage.device.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(toasts)
                .environment(sports)
                .environment(\.locale, (AppLanguage(rawValue: language) ?? .ru).locale)
                .overlay(alignment: .top) { ToastOverlay().environment(toasts) }
                .tint(Color.q.blueText)
                // The brand face for every text that doesn't pick a style itself (list rows,
                // toggles, pickers, menus), so nothing falls back to the system font.
                .font(.q(.body))
                // Terms and Privacy open in the app, not the browser.
                .legalLinks()
                // A tap anywhere outside a text field puts the keyboard away.
                .onAppear { KeyboardDismisser.shared.install() }
                // jur://event/<id> (the lock-screen countdown) and other in-app links.
                .onOpenURL { url in
                    guard url.scheme == "jur" else { return }
                    Router.shared.open(path: (url.host ?? "") + url.path)
                }
                // Rebuild the tree when the language changes so every string re-reads.
                .id(language)
        }
    }
}
