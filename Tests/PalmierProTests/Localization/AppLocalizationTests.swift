import Foundation
import Testing
@testable import PalmierPro

@Suite("App localization")
@MainActor
struct AppLocalizationTests {
    @Test func bundledEnglishLocalizationIsAvailable() throws {
        try withDefaults { defaults in
            // 必须钉死语言：不传就跟随系统，在非英文机器上这条测的是别的词条表。
            let localization = AppLocalization(defaults: defaults, preferredLanguages: ["en"])

            #expect(localization.availableLanguages.contains(.language("en")))
            #expect(localization.string("System Language") == "System Language")
            #expect(localization.string(key: "System Language") == "System Language")
            #expect(localization.string(key: "Export Queue") == "Export Queue")
            #expect(localization.string(key: "Moments") == "Moments")
            #expect(localization.string(key: "Spoken") == "Spoken")
            #expect(localization.string(key: "Files") == "Files")
            #expect(localization.string("\(1234) credits") == "1,234 credits")
            #expect(
                BundledResource.bundle.localizedString(
                    forKey: "CFBundleTypeName",
                    value: nil,
                    table: "InfoPlist"
                ) == "Palmier Project"
            )
        }
    }

    @Test(arguments: ["en", "EN"])
    func storedLanguageBecomesActiveAndCanonical(identifier: String) throws {
        try withDefaults { defaults in
            defaults.set(identifier, forKey: AppLanguage.defaultsKey)

            let localization = AppLocalization(defaults: defaults)

            #expect(localization.activeIdentifier == "en")
            #expect(localization.selection == .language("en"))
            #expect(defaults.string(forKey: AppLanguage.defaultsKey) == "en")
            #expect(!localization.requiresRestart)
        }
    }

    @Test(arguments: [
        ("zh-Hans", "导出"),
        ("zh-Hant", "匯出"),
    ])
    func bundledChineseLocalizationCanBeSelected(identifier: String, export: String) throws {
        try withDefaults { defaults in
            defaults.set(identifier, forKey: AppLanguage.defaultsKey)

            let localization = AppLocalization(defaults: defaults)

            #expect(localization.availableLanguages.contains(.language(identifier)))
            #expect(localization.activeIdentifier == identifier)
            #expect(localization.string("Export") == export)
        }
    }

    @Test func unsupportedStoredLanguageFallsBackToSystem() throws {
        try withDefaults { defaults in
            defaults.set("not-a-bundled-language", forKey: AppLanguage.defaultsKey)

            let localization = AppLocalization(defaults: defaults, preferredLanguages: ["en"])

            #expect(localization.activeIdentifier == "en")
            #expect(localization.selection == .system)
            #expect(defaults.string(forKey: AppLanguage.defaultsKey) == "system")
        }
    }

    @Test(arguments: [
        (AppLanguage.language("en"), false),
        (AppLanguage.language("fr"), true),
    ])
    func languageSelectionPersistsAndReportsRestart(
        language: AppLanguage,
        requiresRestart: Bool
    ) throws {
        try withDefaults { defaults in
            let localization = AppLocalization(defaults: defaults, preferredLanguages: ["en"])

            localization.selection = language

            #expect(defaults.string(forKey: AppLanguage.defaultsKey) == language.id)
            #expect(localization.requiresRestart == requiresRestart)
        }
    }

}

private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
    let suiteName = "AppLocalizationTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try body(defaults)
}

/// 界面渲染的那门语言必须**同时**决定：网关要哪一版显示名、日期怎么写。
///
/// 2026-08-30 实测：系统区域中国、界面英文的机器上，整屏英文里模型页全是中文档位名，
/// 项目卡写着「1个月前」。原因是这两处跟的是 `Locale.current`（区域），
/// 不是 `activeIdentifier`（界面语言）。
@Suite("界面语言是唯一的那一门")
@MainActor
struct UILanguageIsSingleSourceTests {
    @Test(arguments: [("en", "en"), ("zh-Hans", "zh"), ("es", "es")])
    func gatewayFollowsTheRenderedLanguage(stored: String, expected: String) throws {
        try withDefaults { defaults in
            defaults.set(stored, forKey: AppLanguage.defaultsKey)
            #expect(AppLocalization(defaults: defaults).gatewayLanguage == expected)
        }
    }

    /// 系统偏好是中文、但用户在 app 里选了英文 —— 网关必须要英文那一版。
    @Test func inAppChoiceBeatsTheSystemRegion() throws {
        try withDefaults { defaults in
            defaults.set("en", forKey: AppLanguage.defaultsKey)
            let localization = AppLocalization(
                defaults: defaults,
                preferredLanguages: ["zh-Hans-CN", "en-US"]
            )
            #expect(localization.gatewayLanguage == "en")
        }
    }

    /// 英文界面里不许出现「1个月前」。
    @Test func relativeDatesUseTheRenderedLanguage() throws {
        try withDefaults { defaults in
            let localization = AppLocalization(defaults: defaults, preferredLanguages: ["en"])
            let now = Date()
            for style in [RelativeDateTimeFormatter.UnitsStyle.full, .short] {
                let text = localization.relativeString(
                    for: now.addingTimeInterval(-60 * 60 * 24 * 40),
                    style: style,
                    relativeTo: now
                )
                #expect(!text.contains(where: { $0.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } }),
                        "英文界面里出现了中文日期：\(text)")
            }
        }
    }
}
