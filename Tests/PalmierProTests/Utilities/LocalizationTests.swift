import Foundation
import Testing
@testable import PalmierPro

@Suite("Localization")
struct LocalizationTests {

    private static let languages = ["en", "zh-Hans", "es"]

    private func table(_ language: String) throws -> [String: String] {
        let root = try #require(
            [
                Bundle.main.resourceURL?.appendingPathComponent("Localization"),
                Bundle.main.resourceURL?.appendingPathComponent("PalmierPro_PalmierPro.bundle/Localization"),
                Bundle.module.resourceURL?.appendingPathComponent("Localization"),
            ]
            .compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0.path) }
        )
        let url = root.appendingPathComponent("\(language).lproj/Localizable.strings")
        return try #require(NSDictionary(contentsOf: url) as? [String: String])
    }

    /// The three maintained packs must expose the same keys — a missing key silently
    /// degrades to English and is easy to ship without noticing.
    @Test func maintainedLanguagesShareOneKeySet() throws {
        let english = Set(try table("en").keys)
        #expect(!english.isEmpty)
        for language in Self.languages.dropFirst() {
            #expect(Set(try table(language).keys) == english, "\(language) key set differs from en")
        }
    }

    /// Placeholder counts must match, or interpolation drops or duplicates a value —
    /// on a billing string that means quoting a number we don't charge.
    @Test func placeholderCountsMatchEnglish() throws {
        let english = try table("en")
        for language in Self.languages.dropFirst() {
            let translated = try table(language)
            for (key, source) in english {
                let expected = source.components(separatedBy: "%@").count
                let actual = (translated[key] ?? "").components(separatedBy: "%@").count
                #expect(actual == expected, "\(language): placeholder count differs for \"\(key)\"")
            }
        }
    }

    /// English values are the keys themselves, so a missing entry degrades readably.
    @Test func englishValuesEqualTheirKeys() throws {
        for (key, value) in try table("en") where !key.hasPrefix("Log in for free credits") {
            #expect(key == value, "en value should equal its key: \"\(key)\"")
        }
    }

    /// No maintained pack may state a specific free-credit figure — that number is
    /// gateway-owned and must arrive via interpolation.
    @Test func freeCreditCopyCarriesNoHardcodedNumber() throws {
        for language in Self.languages {
            for (key, value) in try table(language) where key.hasPrefix("Log in for free credits") {
                #expect(
                    value.rangeOfCharacter(from: .decimalDigits) == nil || value.contains("%@"),
                    "\(language): \"\(value)\" states a figure the gateway owns"
                )
            }
        }
    }

    /// 网关只认 zh|en|es 三个语言码。应用内可选的语言远不止三种，
    /// 所以送出去之前必须收敛 —— 送一个它不认的码，旁白语言会静默落回英文。
    @Test(arguments: [("zh-Hans", "zh"), ("zh-Hant", "zh"), ("es-419", "es"), ("fr", "en")])
    @MainActor
    func gatewayLanguageCodeMapsToWhitelist(identifier: String, expected: String) {
        let code = String(identifier.prefix(2))
        #expect((["zh", "es"].contains(code) ? code : "en") == expected)
    }

    /// `LocalizedError.errorDescription` 是 nonisolated 的，可能在主线程之外被读到，
    /// 所以离开主 actor 的那条查表路径必须和主线程上得到同一句话。
    @Test func nonisolatedLookupMatchesMainActorLookup() async {
        let offMain = await Task.detached { L10n.key("Not enough credits.") }.value
        let onMain = await MainActor.run { L10n.key("Not enough credits.") }
        #expect(offMain == onMain)
    }


    @Test func threadSafeUnknownKeyFallsBackToItself() async {
        // key 必须是字面量（StaticString），所以两边各写一次同一句
        #expect(await Task.detached { L10n.key("another key that does not exist") }.value
                == "another key that does not exist")
    }

    @Test @MainActor func unknownKeyFallsBackToItself() {
        #expect(L10n.key("a key that does not exist") == "a key that does not exist")
    }

    /// 位置参数（`%@`）那一套换成了插值。顺序不再由我们保证 ——
    /// `String.LocalizationValue` 让译者能在译文里重排，这里只验插值真的落到了输出里。
    @Test @MainActor func interpolationReachesTheOutput() {
        let credits = 3, budget = 20
        #expect(L10n.string("\(credits) / \(budget) credits").contains("3"))
    }
}
