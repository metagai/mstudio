import Foundation
import Observation

/// Runtime-switchable localization.
///
/// Keys are the English source strings, so a missing entry degrades to readable English
/// rather than a key name. Lookup order is selected language → English → the key itself.
///
/// Only en / zh-Hans / es are maintained. The four inherited packs (fr, de, ja, pt-BR) are
/// deliberately left as-is; anything missing there falls back to English.
///
/// `L("…")` reads `L10n.shared.language`, so calling it inside a SwiftUI `body` registers the
/// dependency and the view re-renders when the language changes — no restart.
@Observable
@MainActor
final class L10n {
    static let shared = L10n()

    enum Language: String, CaseIterable, Identifiable, Sendable {
        case system
        case en
        case zhHans = "zh-Hans"
        case es

        var id: String { rawValue }

        /// Shown in its own language — a picker you can't read is useless when you're lost.
        var label: String {
            switch self {
            case .system: return "System"
            case .en: return "English"
            case .zhHans: return "简体中文"
            case .es: return "Español"
            }
        }
    }

    private static let defaultsKey = "metag.language"

    /// Persisted across launches.
    var language: Language {
        didSet {
            guard language != oldValue else { return }
            UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey)
            table = Self.loadTable(for: resolved)
        }
    }

    /// The concrete pack in use once `.system` is resolved.
    var resolved: Language {
        guard language == .system else { return language }
        return Self.matchSystem()
    }

    private var table: [String: String] {
        didSet { Snapshot.shared.replace(table) }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.defaultsKey)
        let initial = stored.flatMap(Language.init(rawValue:)) ?? .system
        language = initial
        let concrete = initial == .system ? Self.matchSystem() : initial
        table = Self.loadTable(for: concrete)
        Snapshot.shared.replace(table)
    }

    /// Lock-guarded mirror of the active table for callers that cannot hop to the main actor.
    /// `LocalizedError.errorDescription` is a nonisolated synchronous property and may be read
    /// from any thread, so it cannot go through the observable path.
    private final class Snapshot: @unchecked Sendable {
        static let shared = Snapshot()
        private let lock = NSLock()
        private var table: [String: String] = [:]
        let english = L10n.loadTable(for: .en)

        func replace(_ new: [String: String]) {
            lock.lock(); defer { lock.unlock() }
            table = new
        }

        func lookup(_ key: String) -> String {
            lock.lock(); defer { lock.unlock() }
            return table[key] ?? english[key] ?? key
        }
    }

    /// Off-main lookup. Does not participate in observation, so a view using it will not
    /// re-render on a language change — use `L(_:)` for anything on screen.
    nonisolated static func threadSafe(_ key: String, _ args: [String] = []) -> String {
        substitute(Snapshot.shared.lookup(key), args)
    }

    nonisolated private static func substitute(_ source: String, _ args: [String]) -> String {
        var out = source
        for arg in args {
            guard let range = out.range(of: "%@") else { break }
            out.replaceSubrange(range, with: arg)
        }
        return out
    }

    /// Maps the system's preferred languages onto what we actually maintain.
    private static func matchSystem() -> Language {
        for code in Locale.preferredLanguages {
            let lower = code.lowercased()
            if lower.hasPrefix("zh-hans") || lower == "zh" || lower.hasPrefix("zh-cn") { return .zhHans }
            if lower.hasPrefix("es") { return .es }
            if lower.hasPrefix("en") { return .en }
        }
        return .en
    }

    func callAsFunction(_ key: String) -> String {
        table[key] ?? Snapshot.shared.english[key] ?? key
    }

    /// Interpolating lookup. Placeholders are `%@`; values are substituted in order.
    func format(_ key: String, _ args: [String]) -> String {
        Self.substitute(callAsFunction(key), args)
    }

    // MARK: - Loading

    /// `Resources/Localization` is `.copy`'d, so the `.lproj` folders sit one level deeper than
    /// the bundle root and standard `NSLocalizedString` lookup never finds them. Read them directly.
    nonisolated static func loadTable(for language: Language) -> [String: String] {
        guard let root = localizationRoot() else { return [:] }
        let url = root
            .appendingPathComponent("\(language.rawValue).lproj")
            .appendingPathComponent("Localizable.strings")
        guard let dict = NSDictionary(contentsOf: url) as? [String: String] else {
            Log.app.warning("L10n: no strings table at \(url.path)")
            return [:]
        }
        return dict
    }

    nonisolated private static func localizationRoot() -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let candidates = [
            resourceURL.appendingPathComponent("Localization"),
            resourceURL.appendingPathComponent("PalmierPro_PalmierPro.bundle/Localization"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// BCP-47 code for the gateway's `lang` field (`zh` | `en` | `es`).
    var gatewayLanguageCode: String {
        switch resolved {
        case .zhHans: return "zh"
        case .es: return "es"
        default: return "en"
        }
    }
}

/// Localized lookup. Call inside a SwiftUI `body` so language changes re-render the view.
@MainActor
func L(_ key: String) -> String { L10n.shared(key) }

/// Localized lookup with `%@` placeholders substituted in order.
@MainActor
func L(_ key: String, _ args: String...) -> String { L10n.shared.format(key, args) }
