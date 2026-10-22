// Values from Config/Secrets.xcconfig, through Info.plist.
import Foundation

enum Config {
    private static func value(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    static var supabaseURL: URL { URL(string: "https://\(value("JurSupabaseHost"))")! }
    static var supabaseAnonKey: String { value("JurSupabaseAnonKey") }
    static var revenueCatKey: String { value("JurRevenueCatKey") }
    static var supportEmail: String { value("JurSupportEmail") }
    static var privacyURL: URL { URL(string: "https://\(value("JurSiteHost"))/privacy")! }
    static var termsURL: URL { URL(string: "https://\(value("JurSiteHost"))/terms")! }
    static var supportURL: URL { URL(string: "https://\(value("JurSiteHost"))/support")! }
    /// The App Store page, for invites.
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6825340225")!
    /// User-created events, Tonight, check-in and event badges.
    static var eventsEnabled: Bool { value("JurEvents").lowercased() == "on" }
    /// Email-code sign-in on the welcome screen. Off until a custom email sender (SMTP) is set up in Supabase:
    /// the built-in sender only sends links, not codes. The hidden password route for App Review stays.
    static let emailSignInEnabled = false

    static var isConfigured: Bool {
        !value("JurSupabaseHost").isEmpty && !value("JurSupabaseHost").contains("your-project")
            && !supabaseAnonKey.isEmpty && !supabaseAnonKey.hasPrefix("your-")
    }
}
