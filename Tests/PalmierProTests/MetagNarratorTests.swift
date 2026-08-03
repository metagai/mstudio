import Testing
@testable import PalmierPro

/// 人格清单现在有三份：workers/narrator.py（出处）、网关的 NARRATORS（入口校验）、
/// 这里（界面标签）。三份分家的那天，用户会点一个选项然后什么都不发生。
@Suite("METAG 旁白音色")
struct MetagNarratorTests {
    @Test("每个人格在三种界面语言下都有标签，且互不相同")
    func labelsExist() {
        for n in MetagNarrator.allCases {
            var seen = Set<String>()
            for lang in ["zh", "en", "es"] {
                let name = n.displayName(for: lang)
                #expect(!name.isEmpty, "\(n.rawValue)/\(lang) 没有标签")
                seen.insert(name)
            }
            #expect(seen.count == 3, "\(n.rawValue) 三种语言的标签有重复")
        }
    }

    @Test("认不出的人格 id 一律当没有 —— 宁可不显示，也不显示一个错的")
    func unknownIsNil() {
        #expect(MetagNarrator(rawValue: "warm_female") == .warmFemale)
        #expect(MetagNarrator(rawValue: "sexy_robot") == nil)
    }

    @Test("五个人格里男女都有 —— 这次事故就是全片只有一个女声")
    func bothGenders() {
        let ids = MetagNarrator.allCases.map(\.rawValue)
        #expect(ids.contains { $0.hasSuffix("_male") })
        #expect(ids.contains { $0.hasSuffix("_female") })
    }

    @Test("未知语言退回英文，而不是空字符串")
    func unknownLangFallsBack() {
        #expect(!MetagNarrator.warmFemale.displayName(for: "ja").isEmpty)
        #expect(MetagNarrator.warmFemale.displayName(for: "ja")
                == MetagNarrator.warmFemale.displayName(for: "en"))
    }
}
