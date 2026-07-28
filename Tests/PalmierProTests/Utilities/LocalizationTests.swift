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

    @Test(arguments: [
        ("zh-Hans", "zh"), ("es", "es"), ("en", "en"),
    ])
    @MainActor
    func gatewayLanguageCodeMapsToWhitelist(pack: String, expected: String) {
        let l10n = L10n.shared
        let original = l10n.language
        defer { l10n.language = original }
        l10n.language = try! #require(L10n.Language(rawValue: pack))
        #expect(l10n.gatewayLanguageCode == expected)
    }

    /// `LocalizedError.errorDescription` is nonisolated and may be read off the main actor,
    /// so the thread-safe path must return the same text the observed path would.
    @Test func threadSafeLookupMatchesObservedLookup() async {
        let key = "Not enough credits."
        let offMain = await Task.detached { L10n.key(key) }.value
        let onMain = await MainActor.run { L10n.key(key) }
        #expect(offMain == onMain)
        #expect(offMain != key || onMain == key)
    }

    @Test func threadSafeLookupSubstitutesPlaceholders() async {
        let text = await Task.detached { L10n.key("METAG request failed (%@).", ["503"]) }.value
        #expect(text.contains("503"))
        #expect(!text.contains("%@"))
    }

    @Test func threadSafeUnknownKeyFallsBackToItself() async {
        let key = "another key that does not exist"
        #expect(await Task.detached { L10n.key(key) }.value == key)
    }

    @Test @MainActor func unknownKeyFallsBackToItself() {
        #expect(L10n.key("a key that does not exist") == "a key that does not exist")
    }

    @Test @MainActor func formatSubstitutesInOrder() {
        #expect(L10n.shared.format("%@ / %@ credits", ["3", "20"]).contains("3"))
    }
}
