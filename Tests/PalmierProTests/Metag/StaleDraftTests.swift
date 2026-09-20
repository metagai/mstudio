import Foundation
import Testing

@testable import PalmierPro

/// 2026-09-20：用户贴进 377 字剧本，请求被网关拒掉，而面板上留着上一条
/// 提示词是 "langlang" 的草案 —— 他看到的是「我写了剧本，它给我一个弹钢琴的视频」。
///
/// 两件事各一条：**旧草案不许留在屏幕上**，**被拒的原因要说成人话**。
@MainActor
struct StaleDraftTests {
    /// 起新草案的那一刻，上一条就该从这个模型里消失。
    ///
    /// 判据落在 `draft()` 这条真路上（而不是直接调 `forgetDraft`）——
    /// 清得早还是清得晚，正是这次事故的全部：清在失败的 catch 里，
    /// 等待的那几十秒照样挂着钢琴。这里没有网络，`draft()` 会在领票那一步
    /// 就返回，**而那之前必须已经清干净**。
    @Test func aNewDraftDropsThePreviousOne() async {
        let model = MetagDraftModel()
        model.stageWaitForTesting(jobId: "9707145e")
        model.applyStreamed(["他站着，不是坐着。", "掌心砸在琴盖上。"])
        #expect(model.jobId != nil && !model.narrations.isEmpty)

        model.prompt = "A white American man walks into a coffee shop…"
        await model.draft()

        #expect(model.jobId == nil, "上一条草案的 jobId 还在，屏幕上就还是上一条片子")
        #expect(model.narrations.isEmpty, "上一条的旁白还在：他会以为我们照着他的剧本写出了这几句")
    }

    /// 「太长」要说出两个数：他写了多少、我们能读多少。
    /// 只说"太长了"，他不知道该删掉多少 —— 于是只会原样再按一次。
    @Test func theTooLongNoteCarriesBothNumbers() {
        let note = MetagDraftModel.note(
            for: MetagGateway.Failure.rejected(400, "prompt_too_long"), chars: 377)
        #expect(note.contains("377"), "没说他写了多少：「\(note)」")
        #expect(note.contains(PromptPaste.promptMaxCharacters.formatted()), "没说上限是多少：「\(note)」")
    }

    /// 带原因码的 400 不许再说"再试一次" —— 重试一定得到同一个结果。
    @Test func aRejected400DoesNotTellHimToRetry() {
        let text = MetagGateway.Failure.rejected(400, "topic_length").message(anonymous: false) ?? ""
        #expect(!text.isEmpty)
        #expect(text.contains("topic_length"), "没带原因码，他报障时说不出是哪一条：「\(text)」")
        #expect(!text.lowercased().contains("try again —"), "还在让他重试：「\(text)」")
    }
}

/// 「能卖」和「能试渲」是两件事。
///
/// 2026-09-20 查实：客户端拿"最便宜的付费档"当"能试渲的档"的代理量，
/// 而服务端那侧是一份手写白名单。线上最便宜的付费档是 wan-flash（7cr，
/// 界面上写着 "Best value 720P"）—— 它不在白名单里，**于是那颗
/// 「免费试渲一镜」对每一个停留在默认档位的人都必然 400**。
/// 而"线上使用 0 次"被我们读成了"没人要"。
@MainActor
struct SampleTierTests {
    static func engine(
        _ id: String, _ credits: Int, sampleable: Bool? = nil, available: Bool = true
    ) -> MetagGateway.Pricing.Engine {
        var e = MetagGateway.Pricing.Engine(
            id: id, name: id, name_i18n: nil, spec: "", resolution: nil, duration_s: nil,
            native_audio: false, credits_per_shot: credits)
        e.sampleable = sampleable
        e.available = available
        return e
    }

    /// 线上那一单的形状：最便宜的付费档不能试渲，它就不许被挑中。
    @Test func theCheapestPaidTierIsNotAutomaticallyTheSampleTier() {
        let list = [
            Self.engine("local", 1, sampleable: false),
            Self.engine("wan-flash", 7, sampleable: false),
            Self.engine("seedance", 34, sampleable: true),
        ]
        let picked = MetagDraftSheet.sampleTier(in: list, selected: "local")
        #expect(picked?.id == "seedance", "挑中的是 \(picked?.id ?? "nil") —— 点下去只会拿一个 400")
    }

    /// 他自己选的那一档不能试渲时，也不许拿它去撞 —— 退到能试的那一档。
    @Test func aSelectedTierThatCannotBeSampledIsNotUsed() {
        let list = [
            Self.engine("local", 1, sampleable: false),
            Self.engine("wan-flash", 7, sampleable: false),
            Self.engine("veo", 56, sampleable: true),
        ]
        #expect(MetagDraftSheet.sampleTier(in: list, selected: "wan-flash")?.id == "veo")
    }

    /// 停售的档不许被挑中 —— 这条在加 `sampleable` 之前就成立，别把它改没了。
    @Test func anUnavailableTierIsStillSkipped() {
        let list = [
            Self.engine("local", 1, sampleable: false),
            Self.engine("seedance", 34, sampleable: true, available: false),
            Self.engine("veo", 56, sampleable: true),
        ]
        #expect(MetagDraftSheet.sampleTier(in: list, selected: "local")?.id == "veo")
    }

    /// **整份报价单都不带这一列 = 服务端还没上它。**
    /// 那时按老规则挑，行为不变 —— 把"不知道"当成"不行"，
    /// 一次回滚就让这个功能从所有人眼前消失。
    @Test func anOldGatewayKeepsTheOldRule() {
        let list = [Self.engine("local", 1), Self.engine("wan-flash", 7), Self.engine("veo", 56)]
        #expect(MetagDraftSheet.sampleTier(in: list, selected: "local")?.id == "wan-flash")
    }

    /// 一档都试不了就**没有这颗按钮** —— 界面那侧靠 nil 判断。
    @Test func nothingSampleableMeansNoButton() {
        let list = [Self.engine("local", 1, sampleable: false), Self.engine("wan-flash", 7, sampleable: false)]
        #expect(MetagDraftSheet.sampleTier(in: list, selected: "local") == nil)
    }
}

/// 草案就绪就自动渲那一镜真的，**按钮和自动走同一段**。
///
/// 判据够不着 SwiftUI 的 `@State`（自动那一次只发一回，靠 `autoSampled` 闩住），
/// 所以断在源码上 —— 同 `FunnelCoverageTests` 锚 `ensureTicket` 的做法。
/// 它盯住的是这次事故的形状：**两条路各写一遍，迟早有一处忘记**
/// （这颗按钮本身就是"同一份名单写三处、加一档漏一处"的产物）。
struct AutoSampleWiringTests {
    static var source: String {
        (try? String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/PalmierPro/Metag/MetagDraftSheet.swift"),
            encoding: .utf8)) ?? ""
    }

    /// 草案就绪那一格上必须真的挂着自动试渲 —— 没有它，这颗按钮又回到
    /// "等他自己发现"，而线上数据说没有人发现过。
    @Test func readyTriggersTheFreeShot() throws {
        let src = Self.source
        let hook = try #require(src.range(of: "onChange(of: model.ready)"))
        let after = String(src[hook.lowerBound...].prefix(1400))
        #expect(after.contains("runSample(auto: true)"),
                "草案就绪没有自动试渲 —— 那一镜又只能等他自己点")
    }

    /// 按钮不许自己再写一遍那段请求。
    @Test func theButtonGoesThroughTheSameFunction() {
        let src = Self.source
        #expect(src.contains("runSample(auto: false)"), "按钮没走同一段")
        // 真正发请求的那一行只应出现一次：在 `runSample` 里。
        #expect(src.components(separatedBy: "MetagGateway.sampleShot(").count - 1 == 1,
                "sampleShot 有两个调用点 —— 两条路会各自长出自己的行为")
    }
}
