import Foundation
import Testing
@testable import PalmierPro

/// **界面不许自己拼价格。**
///
/// ## 为什么这一条要存在
///
/// 2026-09-05 修完"付费墙印 `$9.90`、收银台扣 ¥69"之后，我在
/// `Plan.displayPrice` 的文档注释里写了一句「**不许在界面上硬编码 `$`**」。
///
/// **那句话是备忘，不是判据。** 明天谁新加一个视图写
/// `Text("$\(plan.price_usd)")`，编译过、测试全绿、线上又变回那个 bug ——
/// **没有任何东西会停下来。**
///
/// partner 那天把这一族起了名字：
/// **「一句只出现在人读得到的地方的判断，不是判据，是备忘。
/// 两者的区别不在措辞准不准，在它红的时候有没有东西停下来。」**
/// 同一天我们数出三次同样的失效：网关判据的输出里、`billing.rs` 的注释里、
/// 导演回看的规则说明里，**三句话都说准了，三次都没拦住任何东西。**
///
/// ## 它守的不变量
///
/// ⚠ **这不是假想的风险，是发出去的那一版的实况**（2026-09-06 从标签上核实）：
///
///     metag-v0.1.15  CreditSummaryView.swift:160   `$\(price_usd)` 硬编码
///                    AccountPane.swift:94           同上
///                    `amount_minor` 出现 0 次       ← 那一版根本不知道币种这回事
///
/// 而同一天实测国内收银台按 **cny / 6900** 结算。
/// **一个在国内用 0.1.15 的人，按钮上看到 $9.90，收银台扣他 ¥69。**
///
/// `price_usd` 是网关给的**美元标价**，而用户实际被扣的是
/// `currency` + `amount_minor`（国内那一次性档是 **¥69**，不是 $9.90）。
/// 所以 `price_usd` 只有一个合法消费者：`Plan.displayPrice`。
/// **它出现在界面层的任何一处，都意味着那里正在自己拼一个可能是假的价。**
///
/// ⚠ 这条扫的是源码，而这个仓的规矩是"判据必须是行为"。
/// 例外的理由和 `MetagReachabilityTests` 同一条：**要守的性质是"某段代码
/// 不存在"，而不存在的东西没有行为可测。** 能测行为的那一半已经在
/// `PlanPriceTests` 和 `LivePricingPayloadTests` 里了 —— 这一条只补
/// 它们看不见的那个方向：**新写的代码绕过那个出口。**
@Suite("界面不许自己拼价格")
struct PriceIsNeverHandBuiltTests {

    private func swiftFiles(under directory: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Account
            .deletingLastPathComponent()   // PalmierProTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sources/PalmierPro")
    }

    /// `price_usd` 的唯一合法消费者是 `Plan.displayPrice`（在 MetagGateway.swift 里）。
    @Test func onlyTheModelMayTouchTheDollarPrice() throws {
        let offenders = swiftFiles(under: sourceRoot)
            .filter { $0.lastPathComponent != "MetagGateway.swift" }
            .filter { (try? String(contentsOf: $0, encoding: .utf8))?.contains("price_usd") == true }
            .map { $0.lastPathComponent }
        #expect(offenders.isEmpty,
                """
                这些文件在自己碰美元标价：\(offenders)
                用 `plan.displayPrice` —— 它按网关给的 currency / amount_minor 出，
                而国内那一次性档实收的是 ¥69，不是 $9.90。
                """)
    }

    // ⚠ **这里曾经有第二条判据「displayPrice 必须还在」**，理由是
    //    "出口被删掉的话，上面那条会因为无人引用而恒真"。**变异验证把它否掉了：**
    //    改名或删掉那个出口，会先让 `PlanPriceTests` / `LivePricingPayloadTests`
    //    **编译不过** —— 它永远轮不到第一个红。
    //    **一条永远不可能第一个红的判据是装饰，不是判据。** 所以删掉。
    //    （留这段话是因为下一个人会想到同一件事，而理由比结论省时间。）
}
