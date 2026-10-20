import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case russian = "ru"
    case english = "en"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }
    var selectorTitle: String { self == .russian ? "Русский" : "English" }

    /// Resolves the first supported language in the same order macOS uses:
    /// an app-specific preference first, then the ordered system preferences.
    static func resolve(appSpecific: [String], system: [String]) -> AppLanguage {
        for identifier in appSpecific + system {
            guard let code = Locale(identifier: identifier).language.languageCode?.identifier.lowercased() else { continue }
            if code == AppLanguage.russian.rawValue { return .russian }
            if code == AppLanguage.english.rawValue { return .english }
        }
        return .english
    }
}

/// Thread-safe current presentation language for non-SwiftUI surfaces such as
/// notifications. SwiftUI observes `LocalizationManager.language` directly.
private enum ActiveAppLanguage {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var value: AppLanguage = .english

    static var current: AppLanguage {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    static func set(_ language: AppLanguage) {
        lock.lock()
        value = language
        lock.unlock()
    }
}

@MainActor
@Observable
final class LocalizationManager {
    static let shared = LocalizationManager()
    static let languageDidChange = Notification.Name("Insomnia.LanguageDidChange")

    var language: AppLanguage {
        didSet {
            guard oldValue != language else { return }
            ActiveAppLanguage.set(language)
            NotificationCenter.default.post(name: Self.languageDidChange, object: nil)
        }
    }

    init(language: AppLanguage = .english) {
        self.language = language
        ActiveAppLanguage.set(language)
    }

    /// Reads only the app's language preference. No preference or config file
    /// is written; manual selection lasts for this process only.
    func resolveAtLaunch(
        appSpecific: [String],
        system: [String]
    ) {
        language = AppLanguage.resolve(appSpecific: appSpecific, system: system)
    }

    static func macOSPreferences(bundle: Bundle = .main, defaults: UserDefaults = .standard) -> (appSpecific: [String], system: [String]) {
        let appSpecific = bundle.bundleIdentifier
            .flatMap { defaults.persistentDomain(forName: $0)?["AppleLanguages"] as? [String] } ?? []
        return (appSpecific, Locale.preferredLanguages)
    }
}

enum L10n {
    static func string(_ key: String, language: AppLanguage = ActiveAppLanguage.current) -> String {
        localizedBundle(for: language).localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func format(_ key: String, language: AppLanguage = ActiveAppLanguage.current, _ arguments: CVarArg...) -> String {
        String(format: string(key, language: language), locale: language.locale, arguments: arguments)
    }

    /// Localizes an already-composed presentation string. Format keys in the
    /// catalogs let this translate dynamic messages at the UI boundary while
    /// leaving the underlying error and recovery data intact.
    static func presentation(_ source: String, language: AppLanguage = ActiveAppLanguage.current) -> String {
        presentation(source, language: language, depth: 0)
    }

    private static func presentation(_ source: String, language: AppLanguage, depth: Int) -> String {
        guard language == .russian else { return source }
        let direct = string(source, language: language)
        if direct != source { return direct }
        guard depth < 4 else { return source }

        for template in formatTemplates() {
            guard let captures = capture(source, using: template) else { continue }
            let arguments: [CVarArg] = zip(template.types, captures).map { type, value in
                if type == .integer { return (Int(value) ?? 0) as CVarArg }
                return presentation(value, language: language, depth: depth + 1) as CVarArg
            }
            return String(format: string(template.key, language: language), locale: language.locale, arguments: arguments)
        }
        return source
    }

    static func plural(_ key: String, count: Int, language: AppLanguage = ActiveAppLanguage.current) -> String {
        let category: String
        if language == .russian {
            let n = abs(count) % 100
            let last = n % 10
            if last == 1 && n != 11 { category = "one" }
            else if (2...4).contains(last) && !(12...14).contains(n) { category = "few" }
            else { category = "many" }
        } else {
            category = count == 1 ? "one" : "other"
        }

        guard let path = localizedBundle(for: language).path(forResource: "Localizable", ofType: "stringsdict"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: [String: Any]],
              let entry = plist[key],
              let forms = entry["count"] as? [String: String],
              let format = forms[category] ?? forms["other"]
        else { return "\(count) \(key)" }
        return String(format: format, locale: language.locale, arguments: [count])
    }

    static func availableLocalizations(in bundle: Bundle = .module) -> Set<String> {
        Set(bundle.localizations.compactMap { localization in
            let code = Locale(identifier: localization).language.languageCode?.identifier ?? localization
            return AppLanguage(rawValue: code)?.rawValue
        })
    }

    private enum PlaceholderType { case string, integer }
    private struct FormatTemplate { let key: String; let regex: NSRegularExpression; let types: [PlaceholderType] }

    private static func localizedBundle(for language: AppLanguage) -> Bundle {
        guard let url = Bundle.module.url(forResource: language.rawValue, withExtension: "lproj"),
              let bundle = Bundle(url: url) else { return .module }
        return bundle
    }

    private static let templates: [FormatTemplate] = {
        guard let url = Bundle.module.url(forResource: "Localizable", withExtension: "strings"),
              let data = try? Data(contentsOf: url),
              let keys = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String]
        else { return [] }
        return keys.keys.compactMap(makeTemplate).sorted { $0.key.count > $1.key.count }
    }()

    private static func formatTemplates() -> [FormatTemplate] { templates }

    private static func makeTemplate(_ key: String) -> FormatTemplate? {
        var pattern = "^"
        var types: [PlaceholderType] = []
        var index = key.startIndex
        while index < key.endIndex {
            if key[index] == "%", key.index(after: index) < key.endIndex {
                let next = key[key.index(after: index)]
                if next == "@" {
                    pattern += "(.+?)"
                    types.append(.string)
                    index = key.index(after: key.index(after: index))
                    continue
                } else if next == "d" {
                    pattern += "([+-]?\\d+)"
                    types.append(.integer)
                    index = key.index(after: key.index(after: index))
                    continue
                } else if next == "%" {
                    pattern += "%"
                    index = key.index(after: key.index(after: index))
                    continue
                }
            }
            pattern += NSRegularExpression.escapedPattern(for: String(key[index]))
            index = key.index(after: index)
        }
        guard !types.isEmpty else { return nil }
        pattern += "$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return FormatTemplate(key: key, regex: regex, types: types)
    }

    private static func capture(_ source: String, using template: FormatTemplate) -> [String]? {
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = template.regex.firstMatch(in: source, range: range) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: source) else { return nil }
            return String(source[range])
        }
    }
}
