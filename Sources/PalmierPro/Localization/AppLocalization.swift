import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class AppLocalization {
    static let shared = AppLocalization()

    let activeIdentifier: String
    let activeLocale: Locale
    let availableLanguages: [AppLanguage]

    var selection: AppLanguage {
        didSet {
            guard selection != oldValue else { return }
            defaults.set(selection.id, forKey: AppLanguage.defaultsKey)
        }
    }

    var requiresRestart: Bool {
        (selection.identifier ?? systemIdentifier) != activeIdentifier
    }

    private let defaults: UserDefaults
    private let localizedBundle: Bundle
    private let systemIdentifier: String
    /// 两种粒度各一个，init 里定好。**不能懒建缓存** —— 这是个 @Observable，
    /// 写一次字典就会让所有读过它的卡片重绘。
    @ObservationIgnored private let fullRelative = RelativeDateTimeFormatter()
    @ObservationIgnored private let shortRelative = RelativeDateTimeFormatter()

    init(
        defaults: UserDefaults = .standard,
        resourceBundle: Bundle = BundledResource.bundle,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        self.defaults = defaults

        let resources = Self.localizationResources(in: resourceBundle)
        let identifiers = resources.map(\.identifier)
        availableLanguages = identifiers.map(AppLanguage.language)
        let resolvedSystemIdentifier = Self.preferredIdentifier(
            in: resources,
            preferredLanguages: preferredLanguages
        )
        systemIdentifier = resolvedSystemIdentifier

        let storedLanguage = AppLanguage.stored(in: defaults)
        let validLanguage: AppLanguage
        if let identifier = storedLanguage.identifier, identifiers.contains(identifier) {
            validLanguage = .language(identifier)
        } else {
            validLanguage = .system
        }
        if defaults.string(forKey: AppLanguage.defaultsKey).map({ $0 != validLanguage.id }) == true {
            defaults.set(validLanguage.id, forKey: AppLanguage.defaultsKey)
        }

        selection = validLanguage
        let resolvedActiveIdentifier = validLanguage.identifier ?? resolvedSystemIdentifier
        activeIdentifier = resolvedActiveIdentifier
        activeLocale = Locale(identifier: resolvedActiveIdentifier)
        let resourceIdentifier = resources.first { $0.identifier == resolvedActiveIdentifier }?.resourceIdentifier
            ?? resolvedActiveIdentifier
        localizedBundle = Self.localizedBundle(
            for: resourceIdentifier,
            resourceBundle: resourceBundle
        )
        for (formatter, style) in [(fullRelative, RelativeDateTimeFormatter.UnitsStyle.full), (shortRelative, .short)] {
            formatter.unitsStyle = style
            formatter.locale = activeLocale
        }
    }

    /// "1 month ago"。用 `activeLocale`，不是 `Locale.current` —— 后者是**区域**，
    /// 于是一整屏英文的项目卡上写着「1个月前」（2026-08-30 实测）。
    func relativeString(
        for date: Date,
        style: RelativeDateTimeFormatter.UnitsStyle = .full,
        relativeTo now: Date = Date()
    ) -> String {
        (style == .short ? shortRelative : fullRelative).localizedString(for: date, relativeTo: now)
    }

    /// 网关按 `zh` / `en` / `es` 给引擎名和档位说明。它必须跟着**界面真正渲染的那门语言**走。
    ///
    /// 之前跟的是 `Locale.current` —— 那是**区域**，不是界面语言。系统区域中国、
    /// 界面英文的机器上它给 `zh`：一整屏英文里只有模型名是中文（2026-08-30 实测）。
    var gatewayLanguage: String {
        switch activeIdentifier.prefix(2) {
        case "zh": "zh"
        case "es": "es"
        default: "en"
        }
    }

    func string(_ keyAndValue: String.LocalizationValue) -> String {
        String(
            localized: keyAndValue,
            bundle: localizedBundle,
            locale: activeLocale
        )
    }

    func string(key: String) -> String {
        localizedBundle.localizedString(forKey: key, value: nil, table: nil)
    }

    func displayName(for language: AppLanguage) -> String {
        guard let identifier = language.identifier else {
            return string(key: L10n.key("System Language"))
        }
        let locale = Locale(identifier: identifier)
        return locale.localizedString(forIdentifier: identifier) ?? identifier
    }

    private struct LocalizationResource {
        let identifier: String
        let resourceIdentifier: String
    }

    private static func localizationResources(in bundle: Bundle) -> [LocalizationResource] {
        bundle.localizations
            .filter { $0 != "Base" }
            .map {
                LocalizationResource(
                    identifier: Locale(identifier: $0).identifier,
                    resourceIdentifier: $0
                )
            }
            .sorted { lhs, rhs in
                let lhsName = Locale(identifier: lhs.identifier)
                    .localizedString(forIdentifier: lhs.identifier) ?? lhs.identifier
                let rhsName = Locale(identifier: rhs.identifier)
                    .localizedString(forIdentifier: rhs.identifier) ?? rhs.identifier
                return lhsName.localizedStandardCompare(rhsName) == .orderedAscending
            }
    }

    private static func preferredIdentifier(
        in resources: [LocalizationResource],
        preferredLanguages: [String]
    ) -> String {
        return Bundle.preferredLocalizations(
            from: resources.map(\.resourceIdentifier),
            forPreferences: preferredLanguages
        ).first.map { Locale(identifier: $0).identifier } ?? "en"
    }

    private static func localizedBundle(for identifier: String, resourceBundle: Bundle) -> Bundle {
        guard let url = resourceBundle.url(forResource: identifier, withExtension: "lproj"),
              let bundle = Bundle(url: url) else {
            return resourceBundle
        }
        return bundle
    }
}

extension View {
    func appLocalization() -> some View {
        environment(\.locale, AppLocalization.shared.activeLocale)
    }
}

@MainActor
enum L10n {
    nonisolated static func key(_ value: StaticString) -> String {
        value.description
    }

    static func string(_ keyAndValue: String.LocalizationValue) -> String {
        AppLocalization.shared.string(keyAndValue)
    }

    static func string(key: String) -> String {
        AppLocalization.shared.string(key: key)
    }

}
