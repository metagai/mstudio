import Foundation
import Testing
@testable import PalmierPro

/// **他没等到画面就走了 —— Mac 此前量不到这一格。**
///
/// ## 为什么这一条要存在
///
/// 2026-09-06 从生产库拉出来的数：做好的 404 条匿名草案里，
/// **只有 52 条（12.9%）的主人撑到了第一张画面就绪的时刻**（合伙人掐表：17.1 秒）。
/// 而 45/63 的人在**第 10 秒**就不再做任何事 —— 他们在画面出现之前 7 秒就走了。
///
/// 那一格 web 有（`wait_left`），**Mac 一直没有**。
/// 10-04 那十个人是一次性的：**有人在等待中走掉，我们会把它记成"他不喜欢"**，
/// 而那是三种完全不同的失败里最不该混的一种。
///
/// ## 这条判据守的是"两侧比得了"
///
/// 契约不是我发明的，是从**库里已经存在的 studio 事件**上抄的形状：
///
///     {"page": "studio", "at_sec": 0, "frames": 1, "narration": true}
///
/// 合伙人的原话：**字段要和 web 这侧对得上，否则那天我们有两份数却比不了，
/// 而"Mac 上的悬崖和 web 一样吗"正是那天最值钱的问题之一。**
/// 所以这里把三个键名和那个 step 名**钉死**。
@Suite("他没等到就走了")
@MainActor
struct WaitLeftTests {

    /// studio 那侧线上事件用的三个键，一个都不许改名。
    private static let keysWebUses = ["at_sec", "frames", "narration"]

    @Test func theStepNameMatchesWhatWebAlreadySends() {
        #expect(MetagFunnel.Step.waitLeft.rawValue == "wait_left",
                "step 名改了 —— 报表按 'wait_left' 筛，Mac 那半会整个消失")
    }

    /// 等待还没开始就走，不算 `wait_left`（他压根没在等）。
    @Test func leavingBeforeAnyWaitReportsNothing() {
        #expect(MetagDraftModel().noteLeftWhileWaiting() == nil)
    }

    /// 等待中离开：报，而且带齐 web 那三个键。
    @Test func leavingDuringTheWaitCarriesTheSameKeysAsWeb() throws {
        let m = MetagDraftModel()
        m.beginWaitForTesting()
        let meta = try #require(m.noteLeftWhileWaiting(), "等待中离开却什么都没报")
        for k in Self.keysWebUses {
            #expect(meta[k] != nil, "少了 web 也在发的字段 `\(k)` —— 两侧就比不了了")
        }
        #expect((meta["at_sec"] as? Int) ?? -1 >= 0, "at_sec 不是个非负整数")
    }

    /// **看到草案之后再关窗，不算走。** 不断这一条的话，
    /// 每一次成功的草案都会尾随一条 `wait_left`，而那一格会变成恒真的噪声。
    @Test func leavingAfterTheDraftArrivedIsNotLeaving() {
        let m = MetagDraftModel()
        m.beginWaitForTesting()
        m.markDraftSeenForTesting()
        #expect(m.noteLeftWhileWaiting() == nil, "看到草案之后关窗被记成了流失")
    }

    /// 只报一次 —— 一次等待里发两条会让分母虚高。
    @Test func itReportsAtMostOncePerWait() {
        let m = MetagDraftModel()
        m.beginWaitForTesting()
        #expect(m.noteLeftWhileWaiting() != nil)
        #expect(m.noteLeftWhileWaiting() == nil, "同一次等待报了两条")
    }
}
