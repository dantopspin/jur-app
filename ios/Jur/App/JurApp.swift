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
                // Rebuild the tree when the language changes so every string re-reads.
                .id(language)
        }
    }
}
