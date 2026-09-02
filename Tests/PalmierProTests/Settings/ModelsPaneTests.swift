import Foundation
import Testing
@testable import PalmierPro

/// **一张只有名字和开关的库存清单，不是一套可以挑的积木。**
///
/// 创始人要的是"如乐高般的模块化设计，每一个 component 都精致、有趣"。
/// 而设置里的模型页原来是：一排名字 + 一排开关。他看不出"前沿"和"专业"
/// 差在哪、贵不贵、什么时候该用它 —— 只能靠猜。
///
/// 而这两件事**报价单里本来就有**（`blurb` 和 `credits_per_shot`），
/// 草案表那边早就在显示，只是目录把它们扔掉了。
@Suite("模型页")
struct ModelsPaneTests {
    private static func source(_ name: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PalmierPro/\(name)")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// 目录不许再把这两件事扔掉。
    @Test func theCatalogKeepsWhatThePriceListSaid() {
        let engine = MetagGateway.Pricing.Engine(
            id: "seedance", name: "Seedance", name_i18n: nil, spec: "1080p · 5s",
            resolution: "1080p", duration_s: 5, native_audio: false,
            credits_per_shot: 34, blurb_i18n: ["en": "Best for close-ups"]
        )
        let entry = ModelCatalog.videoEntry(from: engine, language: "en")
        #expect(entry.blurb == "Best for close-ups", "目录又把 blurb 扔掉了")
        #expect(entry.creditsPerShot == 34, "目录又把单价扔掉了")
    }

    /// 这一屏要说出"适合拍什么"和"多少钱一镜"。
    @Test func eachModelSaysWhatItIsForAndWhatItCosts() {
        let src = Self.source("Settings/ModelsPane.swift")
        #expect(src.contains("row.blurb"), "又变回一排只有名字的开关了")
        #expect(src.contains("row.creditsPerShot"),
                "挑一档就是在花钱，而这一屏一个数字都没有")
    }

    /// **没有就不说** —— 不给一句凑出来的介绍，也不印一个猜的价。
    @Test func nothingIsInvented() {
        let src = Self.source("Settings/ModelsPane.swift")
        #expect(src.contains("if let blurb = row.blurb"))
        #expect(src.contains("if let price = row.creditsPerShot"))
    }
}
