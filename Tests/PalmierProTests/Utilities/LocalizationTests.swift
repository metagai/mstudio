import Foundation
import Testing
@testable import PalmierPro

@Suite("Localization")
struct LocalizationTests {

    /// **28 张词条表全都发出去了** —— 语言列表是从 bundle 里现有的
    /// `.lproj` 推出来的（`AppLocalization.localizationResources`），
    /// 没有白名单。所以判据的分母也必须是全部，不是我熟的那三个。
    ///
    /// ## 2026-09-04：这一行原来写的是 `["en", "zh-Hans", "es"]`
    ///
    /// 于是「每一句英文都有翻译」这条判据一直绿，而**另外 25 个语言
    /// 每个都缺 356–361 句**（约 26% 的界面），包括全部计费文案。
    /// 一个德语用户选了德语，看到的价格那一行是英文。
    ///
    /// 判据没写坏，是**分母被缩小了** —— 它诚实地回答了一个太小的问题。
    private static let languages: [String] = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PalmierPro/Resources/Localization")
        let all = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [])
            .filter { $0.hasSuffix(".lproj") }
            .map { String($0.dropLast(6)) }
            .sorted()
        return ["en"] + all.filter { $0 != "en" }
    }()

    /// 现在缺着的那些。**这不是"它们不用翻"，是"它们还没翻"** ——
    /// 记进基线只为了让**新增的**英文串不能再悄悄少一份翻译。
    /// 数字印在失败信息里，它自己会提醒下一个人。
    private static let untranslatedBaseline: Set<String> = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tests/PalmierProTests/Utilities/untranslated-baseline.txt")
        let text = (try? String(contentsOf: root, encoding: .utf8)) ?? ""
        // **按语言登记，不是并集。** 并集会让补齐的语言静悄悄退回去 ——
        // 那个键还在名单里，删掉一句判据不会红（分母比真实大，假绿的第二种）。
        return Set(text.split(separator: "\n").map(String.init)
            .filter { !$0.isEmpty && !$0.hasPrefix("#") })
    }()

    /// 读**源码目录里那份词典**，不是构建产物。
    ///
    /// ## 这三条判据一直绿，靠的是 `.build` 里一个陈旧目录
    ///
    /// 上一版在 bundle 里找一个 `Localization/` 子目录 —— 而
    /// `Package.swift` 用的是 `.process("Resources/Localization")`，
    /// 它把 `.lproj` **摊到 bundle 根上**：那个子目录从来就不该存在。
    ///
    /// 它能被找到，是因为构建缓存里躺着更早一次 `.copy` 留下的副本。
    /// 2026-09-02 我为了腾磁盘删掉 `.build/arm64-apple-macosx` 做全量重编，
    /// 三条判据当场红 —— **它们此前一直在读一份旧词典。**
    ///
    /// > 判据的第一件事不是"它对不对"，是"它是不是这一次的"
    /// > （docs/lessons.md 第三十五条）。
    ///
    /// 源码目录是唯一真源：`check-l10n.py` 和 `AppearanceTests` 读的也是它。
    private func table(_ language: String) throws -> [String: String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Utilities
            .deletingLastPathComponent()   // PalmierProTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // 仓库根
            .appendingPathComponent("Sources/PalmierPro/Resources/Localization")
        #expect(FileManager.default.fileExists(atPath: root.path),
                "词典目录找不着了：\(root.path)")
        let url = root.appendingPathComponent("\(language).lproj/Localizable.strings")
        return try #require(NSDictionary(contentsOf: url) as? [String: String])
    }

    /// **每一句英文都要有译文** —— 缺一句就静默回落成英文，
    /// 而中文界面里冒出一句英文没有任何地方会红。
    ///
    /// 断言的是**包含**，不是相等：
    /// zh/es 里还留着 157 条上游遗留的条目（源码里已经没人用了）。
    /// 那个方向是**死重**，这个方向是**用户看到英文** ——
    /// 拿相等去判，会让一堆无害的陈旧条目盖住那 40 句真的缺翻译。
    /// （2026-09-02：这条判据此前一直在读 `.build` 里一个陈旧目录，
    /// 换成读源码之后当场翻出那 40 句。）
    @Test func everyEnglishStringHasATranslation() throws {
        let english = Set(try table("en").keys)
        #expect(!english.isEmpty)
        for language in Self.languages.dropFirst() {
            let missing = english.subtracting(try table(language).keys)
            let owedHere = Set(Self.untranslatedBaseline
                .filter { $0.hasPrefix("\(language)\t") }
                .map { String($0.dropFirst(language.count + 1)) })
            let unregistered = missing.subtracting(owedHere).sorted()
            let owed = missing.count - unregistered.count
            #expect(unregistered.isEmpty,
                    "\(language) 新少了 \(unregistered.count) 句（基线里已有 \(owed) 句欠账）—— 界面上那几处会是英文：\(unregistered.prefix(5))")
        }
    }

    /// Placeholder counts must match, or interpolation drops or duplicates a value —
    /// on a billing string that means quoting a number we don't charge.
    @Test func placeholderCountsMatchEnglish() throws {
        let english = try table("en")
        for language in Self.languages.dropFirst() {
            let translated = try table(language)
            for (key, source) in english {
                // **没翻的键在这里不算错** —— 它回落成英文，占位符自然对得上。
                // 缺翻译由 everyEnglishStringHasATranslation 管，
                // 两条判据各答各的问题；混在一起会让 25 个语言的欠账
                // 在这里炸成 1900 条噪音，把真正的占位符错埋掉。
                guard let value = translated[key] else { continue }
                // 数的是**占位符**，不是 `%@` 这一种写法。
                // 语序跟英文不一样的语言得写 `%2$@ … %1$@`（zh-Hans 那条
                // "%@ of %@ shots are in" 就是），按字面切 "%@" 会把它数成 0。
                let expected = Self.placeholders(in: source)
                let actual = Self.placeholders(in: value)
                #expect(actual == expected, "\(language): placeholder count differs for \"\(key)\"")
            }
        }
    }

    /// `%@`、`%1$@`、`%d` 都算一个。
    static func placeholders(in s: String) -> Int {
        s.matches(of: /%(\d+\$)?[@dfs]/).count
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
