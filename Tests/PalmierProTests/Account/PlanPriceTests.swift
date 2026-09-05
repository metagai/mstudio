import Foundation
import Testing
@testable import PalmierPro

/// 付费墙上那个数，必须是他真的会被扣的那个数。
///
/// ## 之前发生的事（2026-09-05）
///
/// Mac 端四处价格显示**全部硬编码 `$`**，而国内区那一次性档在 Stripe 上
/// 按 **¥69** 结算 —— **按钮上印 `$9.90`，收银台扣 ¥69**。
/// 那是一句正对着掏钱的人说的假话，**而付费墙是漏斗最后一格**。
///
/// 更要命的是国内三档订阅：它们在 Stripe 上**没有 cny 价位**
/// （`gateway/src/billing.rs:439`），支付方式只剩 `card / link / cashapp` ——
/// 没有国际信用卡的中国用户**根本付不了**。
/// 所以这一条同时守两件事：**价要真**，**付不了的档不许摆出价来**。
@Suite("付费墙上那个价")
struct PlanPriceTests {

    private static func plan(
        id: String = "pack", usd: Double = 9.9, interval: String = "once",
        currency: String? = nil, minor: Int? = nil, available: Bool? = nil
    ) -> MetagGateway.Pricing.Plan {
        var p = MetagGateway.Pricing.Plan(
            id: id, price_usd: usd, interval: interval, credits: 220)
        p.currency = currency
        p.amount_minor = minor
        p.available = available
        return p
    }

    /// **这一条就是那个 bug 本身。** 国内那一档实收 ¥69，屏幕上不许再出现 `$`。
    @Test func aChineseYuanPlanNeverRendersADollarSign() throws {
        let shown = try #require(Self.plan(currency: "cny", minor: 6900).displayPrice)
        #expect(!shown.contains("$"), "国内档印出了美元符号：\(shown)")
        #expect(shown.contains("69"), "金额没印对：\(shown)")
    }

    /// 美元档照旧 —— 修一个区不许弄坏另一个区。
    @Test func aDollarPlanStillRendersDollars() throws {
        let shown = try #require(Self.plan(currency: "usd", minor: 990).displayPrice)
        #expect(shown.contains("9.90"), "金额没印对：\(shown)")
        #expect(!shown.contains("¥"), "美元档印出了人民币符号：\(shown)")
    }

    /// **付不了的档不许摆出价来。** 显示一个他付不了的价比不显示更坏：
    /// 他会点下去，然后在收银台前才发现付不了。
    @Test func anUnavailablePlanShowsNoPriceAtAll() {
        #expect(Self.plan(currency: "usd", minor: 990, available: false).displayPrice == nil)
    }

    /// 老网关不回这三个字段时，行为必须和从前**一模一样** ——
    /// 一次回滚不该让所有价格从界面上消失，也不该让金额变样。
    @Test func anOldGatewayWithoutTheNewFieldsStillShowsTheOldPrice() throws {
        let shown = try #require(Self.plan(usd: 29.9).displayPrice)
        #expect(shown.contains("29.90"), "回退口径变了：\(shown)")
        #expect(Self.plan(usd: 29.9).isAvailable, "字段缺失时必须按可售处理")
    }

    /// 金额只信 `amount_minor`。**不许用 `price_usd` 去折算另一个币种** ——
    /// 那等于我们自己编一个汇率印在付费墙上。
    @Test func theAmountComesFromTheGatewayNotFromAConversion() throws {
        // 同一个 price_usd，两个区结算的数完全不同：这正是不能折算的理由。
        let cn = try #require(Self.plan(usd: 9.9, currency: "cny", minor: 6900).displayPrice)
        let us = try #require(Self.plan(usd: 9.9, currency: "usd", minor: 990).displayPrice)
        #expect(cn.contains("69"))
        #expect(us.contains("9.90"))
        #expect(cn != us, "两个区印出了同一个字符串 —— 币种或金额没生效")
    }

    /// 缺 `amount_minor` 但给了币种时，也不许硬编码符号 —— 由格式化器出。
    @Test func aCurrencyWithoutAnAmountStillFormatsWithThatCurrency() throws {
        let shown = try #require(Self.plan(usd: 9.9, currency: "cny").displayPrice)
        #expect(!shown.contains("$"), "币种给了却印成美元：\(shown)")
    }
}
