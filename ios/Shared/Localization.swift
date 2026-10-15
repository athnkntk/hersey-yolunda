import Foundation
import WidgetKit
import Combine

enum LanguagePreference: String, CaseIterable, Identifiable {
    case system, tr, en
    var id: String { rawValue }
}
enum L10n {
    static let preferenceKey = "appLanguage"
    static var preference: LanguagePreference {
        LanguagePreference(rawValue: SharedStorage.defaults.string(forKey: preferenceKey) ?? "system") ?? .system
    }
    static func resolvedLanguage(preference: LanguagePreference, preferredLanguages: [String]) -> String {
        if preference != .system { return preference.rawValue }
        for tag in preferredLanguages {
            let language = tag.replacingOccurrences(of: "_", with: "-").split(separator: "-").first?.lowercased()
            if language == "tr" || language == "en" { return language! }
        }
        return "en"
    }
    static var language: String { resolvedLanguage(preference: preference, preferredLanguages: Locale.preferredLanguages) }
    static var locale: Locale {
        Locale(identifier: "\(language)_\(Locale.current.region?.identifier ?? (language == "tr" ? "TR" : "US"))")
    }
    static func bundle(language: String) -> Bundle {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
    static func text(_ key: String, language: String? = nil) -> String {
        bundle(language: language ?? self.language).localizedString(forKey: key, value: key, table: "Localizable")
    }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }
}

@MainActor
final class LanguageSettings: ObservableObject {
    @Published var preference: LanguagePreference {
        didSet {
            SharedStorage.defaults.set(preference.rawValue, forKey: L10n.preferenceKey)
            WidgetCenter.shared.reloadAllTimelines()
            NotificationCenter.default.post(name: .init("HYLanguageChanged"), object: nil)
        }
    }
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--uitest-language"), arguments.indices.contains(index + 1),
           let value = LanguagePreference(rawValue: arguments[index + 1]) {
            SharedStorage.defaults.set(value.rawValue, forKey: L10n.preferenceKey)
            preference = value
        } else {
            preference = L10n.preference
        }
    }
}
