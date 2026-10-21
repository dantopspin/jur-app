import SwiftUI

@main
struct JurApp: App {
    @State private var session = SessionStore()
    @State private var toasts = ToastCenter()
    @AppStorage(L10n.storageKey) private var language: String = AppLanguage.device.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(toasts)
                .environment(\.locale, (AppLanguage(rawValue: language) ?? .ru).locale)
                .overlay(alignment: .top) { ToastOverlay().environment(toasts) }
                .tint(Color.q.blueText)
                // Rebuild the tree when the language changes so every string re-reads.
                .id(language)
        }
    }
}
