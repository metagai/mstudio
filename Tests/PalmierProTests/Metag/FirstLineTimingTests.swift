import Foundation
import Testing
@testable import PalmierPro

/// **A0e 的那个数：按下 → 他那句话的第一行上屏。**
///
/// A0e 说要做的是「第 0–17 秒之间，屏幕上要有活的、属于他那句话的东西」，
/// 而**这一刻在 Mac 上一直没被量过**。合伙人 09-07 一秒一秒看了 web
/// （按下 → 12 秒才上屏，其中两段纯等待约 5 秒），而 Mac 走的是
/// "先问再睡、1200ms 一轮"的轮询 —— **两条路形状不一样，
/// 拿他那个数来改我这条路，正是我们数了一整天的那个错。**
///
/// 所以不猜，装一个数，让那十个陌生人自己把真相交出来。
@Suite("第一行上屏用了多久")
@MainActor
struct FirstLineTimingTests {
    /// 毫秒必须来自**一次**读时钟。
    /// 上一版把 `.now` 读了两遍再拼秒和阿托秒 —— 那是两个不同时刻拼出来的数，
    /// 差得小，但它是假的。
    @Test(arguments: [
        (Duration.milliseconds(0), 0),
        (Duration.milliseconds(1), 1),
        (Duration.milliseconds(1_200), 1_200),
        (Duration.seconds(6) + .milliseconds(300), 6_300),
        (Duration.seconds(17), 17_000),
    ])
    func millisecondsComeFromOneReading(duration: Duration, expected: Int) {
        #expect(duration.milliseconds == expected)
    }

    /// 第一行到了才记，而且**只记第一次** —— 后面每一句都覆盖一次的话，
    /// 这个数会变成"最后一句上屏用了多久"，那是另一件事。
    /// ⚠ **时钟必须是注入的。** 第一版让两次推送都用真实 `.now`，
    /// 它们落在同一毫秒里 —— "只记第一次"和"每次都覆盖"算出来一模一样，
    /// 于是我把覆盖那一行改坏，判据照样绿。**一条测不出差别的判据是空的。**
    @Test func onlyTheFirstLineIsTimed() {
        let model = MetagDraftModel()
        let pressed = ContinuousClock.now
        model.beginPressForTesting(at: pressed)
        model.applyStreamed(["雨没停，灯还亮着。"], now: pressed + .seconds(6))
        #expect(model.firstLineMs == 6_000, "第一行上屏没按注入的时钟记：\(model.firstLineMs as Any)")
        model.applyStreamed(["雨没停，灯还亮着。", "她把最后一件衣服叠好。"],
                            now: pressed + .seconds(30))
        #expect(model.firstLineMs == 6_000,
                "第二句把那个数覆盖成了 \(model.firstLineMs as Any) —— 它就不再是「第一行」了")
    }

    /// 没按下过就没有主语 —— 不许凭空造一个数。
    @Test func withoutAPressThereIsNoNumber() {
        let model = MetagDraftModel()
        model.applyStreamed(["一句话"])
        #expect(model.firstLineMs == nil)
    }

    /// 空的/更短的推送不算一行 —— 那是同一份分镜的重复，不是新内容。
    @Test(arguments: [[], [String]()])
    func emptyPushesDoNotCount(lines: [String]) {
        let model = MetagDraftModel()
        model.beginPressForTesting()
        model.applyStreamed(lines, now: .now + .seconds(5))
        #expect(model.firstLineMs == nil)
    }
}
