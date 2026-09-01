import Foundation
import Testing
@testable import PalmierPro

/// 漏斗步骤名是**跨仓库契约**：网关的白名单认不出就 400 `unknown_step`，
/// 而 `MetagFunnel.track` 从不抛、也从不 await —— **失败是完全静默的**。
/// 一格埋点写错一个字母，我们会以为那一步没人走，然后照着那个假数排工。
@Suite("漏斗")
struct MetagFunnelTests {
    private static var gatewaySource: String? {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Metag
            .deletingLastPathComponent()   // PalmierProTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // mac
            .deletingLastPathComponent()   // metag
            .appendingPathComponent("gateway/src/funnel.rs")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    @Test func everyStepIsOnTheGatewayWhitelist() throws {
        // 只在 metag 单仓检出里跑得到。够不到就直说并跳过 ——
        // 一条悄悄变绿的守卫比没有守卫更糟。
        guard let src = Self.gatewaySource else {
            print("跳过：够不到 gateway/src/funnel.rs，这条只在 metag 单仓检出里有效")
            return
        }
        for step in MetagFunnel.Step.allCases {
            #expect(src.contains("\"\(step.rawValue)\""),
                    "网关白名单里没有 \(step.rawValue) —— 这一格会被 400 掉，而客户端不会报错")
        }
    }

    /// 我们量的是**决定**，不是点击。这三格缺任何一个，报价有没有用就看不出来：
    /// 打了字（line_ready）· 敢按下去（draft_started）· 网关真的收下了（paid）。
    @Test func theDecidingStepsAreTracked() {
        let names = Set(MetagFunnel.Step.allCases.map(\.rawValue))
        for required in ["line_ready", "draft_started", "draft_seen", "paid", "film_ready"] {
            #expect(names.contains(required), "缺 \(required) —— 少了它这一段转化算不出来")
        }
    }

    /// **每一条都必须带 page。** `meta` 为 NULL 的事件在报表里和裸脚本
    /// 长得一模一样 —— 真实用户会被当噪音过滤掉。这条盯的是"它带在发送处，
    /// 不是带在调用点"：带在调用点的话，迟早有一处忘记，而忘记是静默的。
    @Test func everyEventCarriesItsClient() throws {
        let src = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/PalmierPro/Metag/MetagFunnel.swift"),
            encoding: .utf8
        )
        #expect(src.contains("\"page\": Self.page"), "page 不是在发送处拼上的")
        #expect(src.contains("\"meta\": payload"), "meta 可能仍然发出 NULL")
        #expect(!src.contains("if let meta { body[\"meta\"] = meta }"),
                "还留着「有 meta 才发」的旧写法 —— 那会让没有 meta 的事件发出 NULL")
    }

    /// **漏斗的默认是"全记"，不是"去重"。**
    ///
    /// 原来默认 `once: true`，于是 line_ready / draft_started / draft_seen
    /// 一次会话只记第一条草案 —— 用户做三条我们只看到一条，
    /// 而"他试了几次"恰恰是这几格存在的全部理由。
    /// 多记看得出来（同一秒两条），少记看不出来。
    @Test func countingEveryAttemptIsTheDefault() throws {
        let src = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/PalmierPro/Metag/MetagFunnel.swift"),
            encoding: .utf8
        )
        #expect(src.contains("once: Bool = false"), "默认又变回去重了 —— 那会静默少记")

        // 一次性的那两格必须显式标出来，否则重复的 landed 会把分母冲大。
        for (file, step) in [("App/AppDelegate.swift", "landed"), ("Metag/MetagAuth.swift", "signedIn")] {
            let s = try String(
                contentsOf: URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent().deletingLastPathComponent()
                    .deletingLastPathComponent().deletingLastPathComponent()
                    .appendingPathComponent("Sources/PalmierPro/\(file)"),
                encoding: .utf8
            )
            #expect(s.contains(".\(step), once: true"), "\(step) 没有显式去重")
        }
    }

    /// `checkout_open` **不该有**：Mac 的内购路径还没开，
    /// 埋一条恒为零的线只会让人以为那一步没人走。
    @Test func noStepForAPathWeDoNotHave() {
        #expect(!MetagFunnel.Step.allCases.map(\.rawValue).contains("checkout_open"))
    }

    /// paid 必须记在**网关收下之后**，不是按钮被点的时候。
    /// 记在按钮上的话，一次失败的批准会让转化率凭空变好而钱一分没进来。
    @Test func paidIsRecordedAfterTheGatewayAccepts() throws {
        let src = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/PalmierPro/Metag/MetagDraftSheet.swift"),
            encoding: .utf8
        )
        let approve = try #require(src.range(of: "try await MetagGateway.approvePreview"))
        let paid = try #require(src.range(of: "MetagFunnel.track(.paid"))
        #expect(paid.lowerBound > approve.upperBound,
                "paid 记在了批准调用之前 —— 那会把失败的批准算成成交")
    }
}

