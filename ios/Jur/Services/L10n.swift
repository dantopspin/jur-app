// In-app language (Kazakh, Russian, English), switchable in Settings without
// restarting. Strings live in Localizable.xcstrings under dotted keys
// ("discover.empty"); "{name}" placeholders are filled here.
import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case kk, ru, en
    var id: String { rawValue }
    var nativeName: String {
        switch self {
        case .kk: "Қазақша"
        case .ru: "Русский"
        case .en: "English"
        }
    }
    /// For dates and numbers.
    var locale: Locale { Locale(identifier: self == .kk ? "kk_KZ" : self == .ru ? "ru_RU" : "en_US") }

    static var device: AppLanguage {
        let code = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "ru"
        return AppLanguage(rawValue: code) ?? .ru
    }
}

enum L10n {
    static let storageKey = "jur.language"

    static var current: AppLanguage {
        get { UserDefaults.standard.string(forKey: storageKey).flatMap(AppLanguage.init(rawValue:)) ?? .device }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
            if Thread.isMainThread { MainActor.assumeIsolated { QNavBar.apply() } }
        }
    }

    private static var bundles: [AppLanguage: Bundle] = [:]
    private static func bundle(for lang: AppLanguage) -> Bundle {
        if let b = bundles[lang] { return b }
        let b = Bundle.main.path(forResource: lang.rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        bundles[lang] = b
        return b
    }

    /// The string for `key` in the current language, with `{placeholders}` filled.
    static func t(_ key: String, _ args: [String: CustomStringConvertible] = [:]) -> String {
        var s = bundle(for: current).localizedString(forKey: key, value: nil, table: nil)
        if s == key, current != .en { // missing translation: fall back to English
            s = bundle(for: .en).localizedString(forKey: key, value: key, table: nil)
        }
        for (k, v) in args { s = s.replacingOccurrences(of: "{\(k)}", with: v.description) }
        return s
    }
}

/// Shorthand used in views: `Text(t("discover.empty"))`.
func t(_ key: String, _ args: [String: CustomStringConvertible] = [:]) -> String { L10n.t(key, args) }

/// A counted string: "48 анкет", "1 анкету", "3 анкеты". Looks up `key_one`, `key_few` or
/// `key_many` by the language's rule (Russian has three forms; English and Kazakh use
/// `_one` for 1 and `_many` for the rest) and fills `{n}`.
func tn(_ key: String, _ n: Int, _ args: [String: CustomStringConvertible] = [:]) -> String {
    let form: String
    switch L10n.current {
    case .ru:
        let m10 = n % 10, m100 = n % 100
        form = m10 == 1 && m100 != 11 ? "one" : (2...4).contains(m10) && !(12...14).contains(m100) ? "few" : "many"
    default:
        form = n == 1 ? "one" : "many"
    }
    var all = args
    all["n"] = n
    return t("\(key)_\(form)", all)
}
