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
