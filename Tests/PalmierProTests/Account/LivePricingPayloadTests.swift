import Foundation
import Testing
@testable import PalmierPro

/// 拿**线上真实报文**验一遍渲染，而不是拿我自己造的数。
///
/// ## 为什么要有这一条
///
/// `PlanPriceTests` 用的是我手搓的 `Plan`——它证明了逻辑对，
/// **但证明不了我的字段名和网关发的对得上**。少一个下划线、
/// 把 `amount_minor` 写成 `amountMinor`，那些测试照样全绿，
/// 而线上会静默落回 `price_usd`：**国内用户又看见 `$9.90`，又被扣 ¥69。**
///
/// 下面两段是 2026-09-05 从两个区 `GET /api/v1/pricing` 抓下来的 `plans` 数组，
/// **一字未改**；`engines` 那一大段与本条无关，替换成空数组，
/// `signup_free_credits` 是解码必需的顶层字段，按线上真值 30 填回。
/// **判据不联网** —— 网络在单测里是不确定性，
/// 而这份报文的价值恰恰在于它是那一刻的事实。
///
/// ⚠ 第一版我写的是"只删了与价格无关的字段"，而我删掉的
/// `signup_free_credits` 恰好是解码必需的 —— 四条判据当场全红。
/// **"与本条无关"和"可以删"是两回事。**
///
/// ⚠ 网关哪天改了字段名，这条会红，而那正是它存在的理由。
@Suite("线上报文喂进来还印得对")
struct LivePricingPayloadTests {

    /// 国内区：三档订阅按美元结算，**一次性档按人民币 ¥69**。
    private static let cn = """
    {"signup_free_credits":30,"engines":[],"plans":[
      {"id":"sub","price_usd":9.9,"interval":"month","credits":300,
       "currency":"usd","amount_minor":990,"available":true,
       "methods":["card","link","cashapp"]},
      {"id":"pro","price_usd":29.9,"interval":"month","credits":950,
       "currency":"usd","amount_minor":2990,"available":true,
       "methods":["card","link","cashapp"]},
      {"id":"studio","price_usd":99.0,"interval":"month","credits":3300,
       "currency":"usd","amount_minor":9900,"available":true,
       "methods":["card","link","cashapp"]},
      {"id":"pack","price_usd":9.9,"interval":"once","credits":220,
       "currency":"cny","amount_minor":6900,"available":true,
       "methods":["card","alipay","link","wechat_pay"]}
    ]}
    """

    /// 海外区：四档都按美元。
    private static let global = """
    {"signup_free_credits":30,"engines":[],"plans":[
      {"id":"pack","price_usd":9.9,"interval":"once","credits":220,
       "currency":"usd","amount_minor":990,"available":true,
       "methods":["card","link","cashapp","alipay","wechat_pay"]}
    ]}
    """

    private static func plans(_ json: String) throws -> [MetagGateway.Pricing.Plan] {
        try JSONDecoder().decode(MetagGateway.Pricing.self, from: Data(json.utf8)).plans
    }

    /// **这一条就是那个 bug 的终点。** 国内那一档实收 ¥69，屏幕上不许再是 `$9.90`。
    @Test func theChinaPackRendersSixtyNineYuanNotNineNinetyDollars() throws {
        let pack = try #require(Self.plans(Self.cn).first { $0.id == "pack" })
        let shown = try #require(pack.displayPrice)
        #expect(shown.contains("69"), "国内一次性档没印出 69：\(shown)")
        #expect(!shown.contains("$"), "国内一次性档还在印美元符号：\(shown)")
    }

    /// 同一份报文里，订阅三档确实是美元 —— **不许把一个区的修法套到另一档上。**
    @Test func theChinaSubscriptionsStillRenderDollars() throws {
        for id in ["sub", "pro", "studio"] {
            let plan = try #require(Self.plans(Self.cn).first { $0.id == id })
            let shown = try #require(plan.displayPrice, "\(id) 没印出价")
            #expect(!shown.contains("¥"), "\(id) 印成了人民币：\(shown)")
        }
    }

    /// 海外那一档没被这次改动碰坏。
    @Test func theGlobalPackStillRendersDollars() throws {
        let pack = try #require(Self.plans(Self.global).first)
        let shown = try #require(pack.displayPrice)
        #expect(shown.contains("9.90"), "海外一次性档金额变了：\(shown)")
    }

    /// **字段名必须真的被解出来。** 少一个下划线，上面几条会静默落回
    /// `price_usd` 而依然绿 —— 所以这里直接断言解码结果，不看渲染。
    @Test func theNewFieldsAreActuallyDecoded() throws {
        let pack = try #require(Self.plans(Self.cn).first { $0.id == "pack" })
        #expect(pack.currency == "cny", "currency 没解出来")
        #expect(pack.amount_minor == 6900, "amount_minor 没解出来")
        #expect(pack.available == true, "available 没解出来")
    }
}
