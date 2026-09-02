import Foundation
import Testing
@testable import PalmierPro

/// **镜数由服务端定，客户端只在用户亲口挑了的时候才传。**
///
/// 2026-09-01 之前客户端有四个地方各写了一个 4。后果：一句写着
/// `one continuous build process`（一镜到底）的提示词，照样被切成四镜、
/// 四镜各自生成 —— 那几个小工人当然每镜长得不一样，
/// 而创始人看到的"人物混乱"就是这个。
///
/// **竞品把同一段话照做，我们改写了它。**
///
/// 而首页那条路（打一句话直接开拍）用户压根没见过那个旋钮，
/// 就已经被定成 4 镜了。只有读过提示词的那一方有资格决定切几镜。
@Suite("镜数")
@MainActor
struct ShotCountTests {
    private static func source(_ name: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PalmierPro/\(name)")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// 默认是"没挑" —— 而不是 4。
    @Test func theDefaultIsToLetTheServerDecide() {
        #expect(MetagDraftModel().chosenShots == nil,
                "又给了一个默认镜数 —— 那等于替每个用户都选了")
    }

    /// 没挑就不往请求里放这个字段。
    @Test func nothingIsSentWhenHeDidNotChoose() {
        let src = Self.source("Metag/MetagGateway.swift")
        #expect(src.contains("if let shots { body[\"shots\"] = shots }"),
                "shots 又被无条件塞进请求了")
        #expect(src.contains("shots: Int? = nil"),
                "preview 又有了一个默认镜数")
    }

    /// **`submit` 不许有默认镜数。** 有默认值就会被不知不觉继承 ——
    /// 那正是四个 4 的来源。
    @Test func submitForcesTheCallerToSayWhatItMeans() {
        let src = Self.source("Metag/MetagGateway.swift")
        #expect(!src.contains("shots: Int = 4"), "又出现了一个默认的 4")
    }

    /// 他挑了就用他的；没挑就用分镜回来之后真实的那个。
    @Test func theKnownCountPrefersHisChoice() {
        let model = MetagDraftModel()
        #expect(model.knownShots == nil, "还什么都不知道时不许编一个数")
        model.chosenShots = 2
        #expect(model.knownShots == 2)
    }

    /// 报价改在**知道真镜数之后**问。
    ///
    /// 原来在起草那一刻就按客户端那个 4 去问 —— 而镜数现在由服务端定，
    /// 那时我们根本不知道会切几镜，报出来的是个假设。
    @Test func theQuoteWaitsUntilTheCountIsReal() throws {
        let src = Self.source("Metag/MetagDraftSheet.swift")
        let quoteCall = try #require(src.range(of: "MetagGateway.quote(prompt: prompt, shots: shots"))
        let poll = try #require(src.range(of: "private func quoteOnce()"))
        #expect(poll.lowerBound < quoteCall.lowerBound)
        #expect(src.contains("guard quote == nil, !askedForQuote, let shots = knownShots"),
                "报价又在不知道镜数的时候发了 —— 那个数是编的")
    }
}
