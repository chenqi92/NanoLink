import Foundation
import Combine

/// Runtime localization engine that mirrors the Flutter app's easy_localization
/// setup: the same `en.json` / `zh.json` string tables are bundled and looked up
/// by dot-path key (e.g. `dashboard.title`). Language can be switched in-app and
/// is persisted; views observing this object rebuild on change.
final class L10n: ObservableObject {
    static let shared = L10n()

    @Published private(set) var language: String

    private var tables: [String: [String: Any]] = [:]
    private static let storageKey = "app_language"

    private init() {
        language = UserDefaults.standard.string(forKey: L10n.storageKey) ?? L10n.systemLanguage()
        load("en")
        load("zh")
    }

    static func systemLanguage() -> String {
        let pref = Locale.preferredLanguages.first ?? "en"
        return pref.hasPrefix("zh") ? "zh" : "en"
    }

    func setLanguage(_ lang: String) {
        guard lang != language else { return }
        language = lang
        UserDefaults.standard.set(lang, forKey: L10n.storageKey)
    }

    private func load(_ lang: String) {
        guard let url = Bundle.main.url(forResource: lang, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        tables[lang] = json
    }

    /// Raw string for a dot-path key with fallback to English, then the key.
    func raw(_ key: String) -> String {
        if let v = L10n.lookup(key, in: tables[language] ?? [:]) { return v }
        if let v = L10n.lookup(key, in: tables["en"] ?? [:]) { return v }
        return key
    }

    private static func lookup(_ key: String, in table: [String: Any]) -> String? {
        var node: Any = table
        for part in key.split(separator: ".") {
            guard let dict = node as? [String: Any], let next = dict[String(part)] else { return nil }
            node = next
        }
        return node as? String
    }

    /// Localize with `{name}`-style named args and/or positional `{}` args.
    func t(_ key: String,
           _ named: [String: CustomStringConvertible] = [:],
           args: [CustomStringConvertible] = []) -> String {
        var s = raw(key)
        for (k, v) in named {
            s = s.replacingOccurrences(of: "{\(k)}", with: v.description)
        }
        for a in args {
            if let range = s.range(of: "{}") {
                s.replaceSubrange(range, with: a.description)
            }
        }
        return s
    }
}

/// Global convenience so non-view code (services/state) can localize too.
func tr(_ key: String,
        _ named: [String: CustomStringConvertible] = [:],
        args: [CustomStringConvertible] = []) -> String {
    L10n.shared.t(key, named, args: args)
}
