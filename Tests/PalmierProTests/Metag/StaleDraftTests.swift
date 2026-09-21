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

/// 两道闸说的不是同一件事，所以不许说同一句话。
///
/// 按 IP 那道（`sample_quota`）是"这条网络今天用过了"——公司/学校/CGNAT
/// 后面几百个人共一个出口，很可能**根本不是他用的**；全站那道
/// （`sample_daily_cap`）是我们今天的免费额度发完了，**那不是他的错**。
/// 拿同一句顶上，他会以为自己做错了什么。
struct SampleQuotaCopyTests {
    @Test func theTwoGatesDoNotShareOneSentence() {
        let ip = MetagGateway.Failure.rejected(429, "sample_quota").message(anonymous: true) ?? ""
        let site = MetagGateway.Failure.rejected(429, "sample_daily_cap").message(anonymous: true) ?? ""
        #expect(!ip.isEmpty && !site.isEmpty)
        #expect(ip != site, "两道闸说了同一句话 —— 其中一句对他是假话")
        // 兜底那句（"Temporarily unavailable"）说明这个码没有自己的文案。
        #expect(!ip.contains("Temporarily"), "按 IP 那道掉进兜底：「\(ip)」")
        #expect(!site.contains("Temporarily"), "全站那道掉进兜底：「\(site)」")
    }

    /// 全站那道**不许把责任说成他的** —— 他一次都没用过也会撞上它。
    @Test func theSiteWideGateDoesNotBlameHim() {
        let site = MetagGateway.Failure.rejected(429, "sample_daily_cap").message(anonymous: true) ?? ""
        #expect(site.lowercased().contains("nothing wrong on your end")
                || site.contains("不是你"),
                "没说清这不是他的错：「\(site)」")
    }
}

/// 免费试渲那一镜**得真的到他眼前**。
///
/// 2026-09-20 我先把"自动去渲"推上去了，然后追交付路径才发现：worker 渲完
/// 写 `sample_ready`，而网关不回、客户端不读、草案播的还是静帧那条 ——
/// 花掉他一人一次的机会、花掉我们约 $0.23，屏幕上什么都不会变。
/// 那一笔被我撤了，等网关回出这三个键（e19166f）才连同展示一起放回来。
@MainActor
struct SampleArrivesOnScreenTests {
    /// **从真响应的形状解出来**，不是手搓一个结构体：
    /// 这条判据要守的正是"网关回的键和我解的键是同一个"。
    /// 原文取自 CTO 在真网关上量到的那一条：
    /// `{"sample_shot": 1, "sample_ready": true, "sample_error": null}`。
    static func job(ready: Bool?, shot: Int?, error: String? = nil) -> MetagGateway.Job {
        func lit(_ v: Bool?) -> String { v.map { $0 ? "true" : "false" } ?? "null" }
        let json = """
        {"job_id": "j", "status": "done", "error": null, "shots": [],
         "cover": null, "shots_done": null, "stage": null,
         "sample_shot": \(shot.map(String.init) ?? "null"),
         "sample_ready": \(lit(ready)),
         "sample_error": \(error.map { "\"\($0)\"" } ?? "null")}
        """
        return try! JSONDecoder().decode(MetagGateway.Job.self, from: Data(json.utf8))
    }

    /// 渲好了就播那一镜。
    @Test func aFinishedSampleIsTheOneWeShow() {
        #expect(MetagDraftModel.readySampleShot(Self.job(ready: true, shot: 1)) == 1)
    }

    /// **没试渲过是 null，不是 false** —— 网关特意不回 false（回了的话
    /// 客户端会显示"正在渲"，而真相是根本没开始）。两种都不许播。
    @Test func nothingToShowBeforeItIsRendered() {
        #expect(MetagDraftModel.readySampleShot(Self.job(ready: nil, shot: nil)) == nil)
        #expect(MetagDraftModel.readySampleShot(Self.job(ready: false, shot: 0)) == nil)
        #expect(MetagDraftModel.readySampleShot(nil) == nil)
    }

    /// `ready` 为真而不知道是哪一镜 —— 那是我们读不懂的状态，
    /// **不是"第 0 镜好了"**。猜一镜播出去，他看到的可能是另一镜。
    @Test func readyWithoutAShotNumberShowsNothing() {
        #expect(MetagDraftModel.readySampleShot(Self.job(ready: true, shot: nil)) == nil)
    }

    /// 渲挂了不播，但**要说出来**（界面那一行读 `sampleFailure`）。
    @Test func aFailedSampleIsNotShownAsAPicture() {
        let failed = Self.job(ready: nil, shot: 0, error: "upstream said no")
        #expect(MetagDraftModel.readySampleShot(failed) == nil)
        let model = MetagDraftModel()
        model.applyJobForTesting(failed)
        #expect(model.sampleFailure == "upstream said no", "渲挂了没有下文，比没渲更伤")
    }
}

/// 免费试渲不许永远挑第 0 镜。
///
/// 2026-09-20 线上实拍两条片子，第 0 镜的提示词分别是
/// "a lone woman stands under a glowing awning…" / "raindrops ripple across
/// oily black asphalt…" —— 建置镜，按电影惯例本来就是静的。而我们**永远只渲
/// 第 0 镜**给陌生人看，于是他唯一那一眼"付费档长什么样"是镜头缓推、人不动。
/// 判据的样本就是那两条真片子的原文。
@MainActor
struct LiveliestShotTests {
    static func shots(_ prompts: [String]) -> [MetagGateway.Job.Shot] {
        let json = "[" + prompts.map {
            let p = $0.replacingOccurrences(of: "\"", with: "\\\"")
            return """
            {"asset":null,"asset_use":null,"narration":"","video":"v","audio":"a","prompt":"\(p)"}
            """
        }.joined(separator: ",") + "]"
        return try! JSONDecoder().decode([MetagGateway.Job.Shot].self, from: Data(json.utf8))
    }

    /// 线上那条片子的原文（a8f80c12，2026-09-20）。第 1 镜里人在数数，
    /// 第 0 镜只是雨打在柏油路上。
    @Test func itPicksTheShotWhereSomeoneDoesSomething() {
        let real = Self.shots([
            "Wide shot from puddle level: raindrops ripple across oily black asphalt reflecting neon signs. A young East Asian woman stands under a translucent plastic awning.",
            "Medium close-up: rain streaks diagonally as a yellow bus passes left-to-right. She counts silently, index finger rising and falling six times.",
            "Over-the-shoulder: a matte-black sedan glides into frame, headlights cutting twin tunnels through rain.",
            "Extreme close-up, macro lens: raindrops bead on the rim of her white paper cup, steam curling faintly.",
        ])
        #expect(MetagDraftModel.liveliestShot(real) == 1,
                "挑中的是第 \(MetagDraftModel.liveliestShot(real)) 镜 —— 又把建置镜端给了陌生人")
    }

    /// **一个动作词都没有时留在第 0 镜。** 分不出来就别乱挑：
    /// 那时至少他看到的是开场，而不是一个随机的中间镜。
    @Test func itStaysOnTheOpenerWhenNothingMoves() {
        #expect(MetagDraftModel.liveliestShot(Self.shots([
            "Wide shot of an empty street at dawn.",
            "Close-up of a cold cup of coffee on a table.",
        ])) == 0)
        #expect(MetagDraftModel.liveliestShot([]) == 0, "没有镜头时不许越界")
    }

    /// **背景动不算。** 车流、雨丝、霓虹闪烁都会动，而主体不动正是我们要避开的那种。
    @Test func backgroundMotionDoesNotCount() {
        let s = Self.shots([
            "Static frame: she lifts her hand and turns her head toward the door.",
            "Traffic passing, blurred headlights streaking, rain falling, neon flickering.",
        ])
        #expect(MetagDraftModel.liveliestShot(s) == 0, "被背景动静骗了")
    }
}

/// **第一条片子默认走会动的那一档。**
///
/// 自研档 1cr/镜最便宜，也最不会动：30 天 461 镜平均 motion 5.66，
/// 而 wan-flash 16.73。默认档决定他第一条片子长什么样，而第一条片子
/// 决定他还回不回来 —— 2026-09-20 那个说「每一帧是镜头 PPT」的用户，
/// 看的就是默认档出的片子。
@MainActor
struct FirstFilmEngineTests {
    static func engines(_ spec: [(String, Int, Bool)]) -> [MetagGateway.Pricing.Engine] {
        let json = "[" + spec.map { id, cr, avail in
            """
            {"id":"\(id)","name":"\(id)","name_i18n":null,"spec":"","resolution":null,
             "duration_s":null,"native_audio":false,"credits_per_shot":\(cr),
             "available":\(avail)}
            """
        }.joined(separator: ",") + "]"
        return try! JSONDecoder().decode([MetagGateway.Pricing.Engine].self, from: Data(json.utf8))
    }

    static let live = engines([("local", 1, true), ("wan-flash", 7, true),
                               ("seedance", 34, true), ("veo", 56, true)])

    /// 第一条片子：挑能用的付费档里最便宜的那一个（今天是 wan-flash）。
    @Test func theFirstFilmGetsTheCheapestTierThatMoves() {
        #expect(MetagDraftSheet.firstFilmEngine(in: Self.live, firstFilm: true) == "wan-flash")
    }

    /// **不是第一条就不动他的选择。** 老用户的默认值是另一件事，
    /// 由他上次选的决定，不该被这条规则覆盖。
    @Test func aReturningUserKeepsTheOldDefault() {
        #expect(MetagDraftSheet.firstFilmEngine(in: Self.live, firstFilm: false) == nil)
    }

    /// **拿不到报价单就不动默认值** —— 网络抖一下不该让他第一条片子换一档。
    @Test func noPricingMeansNoChange() {
        #expect(MetagDraftSheet.firstFilmEngine(in: [], firstFilm: true) == nil)
    }

    /// 停售的档不许被选中，哪怕它更便宜。
    @Test func anUnavailableTierIsNotChosen() {
        let list = Self.engines([("local", 1, true), ("wan-flash", 7, false), ("seedance", 34, true)])
        #expect(MetagDraftSheet.firstFilmEngine(in: list, firstFilm: true) == "seedance")
    }

    /// **不挑自研档** —— 它正是我们要绕开的那一档（它是默认值本身）。
    @Test func itNeverPicksTheInHouseTier() {
        let onlyLocal = Self.engines([("local", 1, true)])
        #expect(MetagDraftSheet.firstFilmEngine(in: onlyLocal, firstFilm: true) == nil)
    }
}
