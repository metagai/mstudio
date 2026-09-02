import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class AppLocalization {
    /// 查一句话要的全部东西：一本词条表和一个 locale。
    ///
    /// **改语言要重启**（`requiresRestart`），所以这两样在一个进程里只写一次，
    /// 之后只读 —— 于是查表不需要主线程。
    ///
    /// 原来它要主线程，`errorDescription` 这类 nonisolated 的地方够不着，
    /// 只好退回 `L10n.key`（把 key 原样返回），而下游没人把它查回来：
    /// 网关的 29 条失败文案全是原样的英文，出现在他最需要看懂的那一刻。
    struct Catalog: Sendable {
        let bundle: Bundle
        let locale: Locale

        /// **自己算得出来，不等谁来装。**
        ///
        /// 第一版是 `Catalog(bundle: .main, locale: .current)`，等着
        /// `AppLocalization.shared` 初始化时装进来。于是**谁都没碰过 shared
        /// 的时候，查表退回 `.main`** —— 那里一个 `.lproj` 都没有，
        /// 整屏是英文。「我的作品」那一屏当场就是这样渲出来的。
        ///
        /// 一个"要等别人来填对"的全局，早晚会在没人填的那条路上被读到。
        /// 现在它自己走一遍和 `AppLocalization.init` 同一套解析。
        nonisolated(unsafe) private(set) static var current = resolve()

        nonisolated static func resolve(
            defaults: UserDefaults = .standard,
            resourceBundle: Bundle = BundledResource.bundle,
            preferredLanguages: [String] = Locale.preferredLanguages
        ) -> Catalog {
            let resources = AppLocalization.localizationResources(in: resourceBundle)
            let system = AppLocalization.preferredIdentifier(
                in: resources, preferredLanguages: preferredLanguages)
            let stored = AppLanguage.stored(in: defaults)
            let identifiers = resources.map(\.identifier)
            let active = (stored.identifier.flatMap { identifiers.contains($0) ? $0 : nil }) ?? system
            let resourceIdentifier =
                resources.first { $0.identifier == active }?.resourceIdentifier ?? active
            return Catalog(
                bundle: AppLocalization.localizedBundle(
                    for: resourceIdentifier, resourceBundle: resourceBundle),
                locale: Locale(identifier: active)
            )
        }

        /// 临时换一本表跑一段。**只给判据用** —— 生产代码里这本表算一次就不再动。
        ///
        /// 存在的理由：`errorDescription` 走的是全局那一份，
        /// 而"它到底有没有查表"这件事，在英文机器上两种写法输出一模一样，
        /// **只有换到非英文才看得出来**。
        static func withCatalog<T>(_ catalog: Catalog, _ body: () throws -> T) rethrows -> T {
            let saved = current
            current = catalog
            defer { current = saved }
            return try body()
        }

        func string(_ keyAndValue: String.LocalizationValue) -> String {
            String(localized: keyAndValue, bundle: bundle, locale: locale)
        }

        func string(key: String) -> String {
            bundle.localizedString(forKey: key, value: nil, table: nil)
        }
    }

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

    /// **这个实例自己那份。** 读全局的话，测试里造出来的
    /// `AppLocalization(preferredLanguages: ["zh-Hans"])` 会悄悄拿到这台机器的
    /// 语言 —— 守卫在中文机器上恒绿、在英文 CI 上恒红，两种都不是在测东西。
    nonisolated let catalog: Catalog
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
        catalog = Catalog(bundle: localizedBundle, locale: activeLocale)
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

    /// **查一句话不该要主线程。**
    ///
    /// 它读的是 `localizedBundle` 和 `activeLocale`，两个 init 之后就不再动的
    /// `let`。原来它是主线程的，于是 `errorDescription` 这类 nonisolated 的地方
    /// 够不着 —— 只好退回 `L10n.key`（把 key 原样返回），而下游没人把它查回来：
    /// 用户在最需要看懂的那一刻，拿到的是一行英文原文。
    nonisolated func string(_ keyAndValue: String.LocalizationValue) -> String {
        catalog.string(keyAndValue)
    }

    nonisolated func string(key: String) -> String {
        catalog.string(key: key)
    }

    func displayName(for language: AppLanguage) -> String {
        guard let identifier = language.identifier else {
            return string(key: L10n.key("System Language"))
        }
        let locale = Locale(identifier: identifier)
        return locale.localizedString(forIdentifier: identifier) ?? identifier
    }

    fileprivate struct LocalizationResource {
        let identifier: String
        let resourceIdentifier: String
    }

    nonisolated fileprivate static func localizationResources(in bundle: Bundle) -> [LocalizationResource] {
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

    nonisolated fileprivate static func preferredIdentifier(
        in resources: [LocalizationResource],
        preferredLanguages: [String]
    ) -> String {
        return Bundle.preferredLocalizations(
            from: resources.map(\.resourceIdentifier),
            forPreferences: preferredLanguages
        ).first.map { Locale(identifier: $0).identifier } ?? "en"
    }

    nonisolated fileprivate static func localizedBundle(for identifier: String, resourceBundle: Bundle) -> Bundle {
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

    nonisolated static func string(_ keyAndValue: String.LocalizationValue) -> String {
        AppLocalization.Catalog.current.string(keyAndValue)
    }

    nonisolated static func string(key: String) -> String {
        AppLocalization.Catalog.current.string(key: key)
    }

}
