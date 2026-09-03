import Foundation
import Testing
@testable import PalmierPro

/// **他付完钱、切回 Mac 的那一刻。**
///
/// 2026-09-02 走查查出：`openCheckout` 把浏览器打开、埋一个漏斗点，然后就结束了 ——
/// 没有 `didBecomeActive`、没有轮询、没有回跳处理。
/// 他付了钱、Stripe 说成功、切回 Mac，**credits 胶囊还是付款前那个数**。
///
/// 他不会再等等，他会发邮件问、或者要求退款 ——
/// **这是整条转化链上最贵的一次断裂，就发生在他刚决定信任我们之后的三秒。**
@Suite("付完钱切回来")
@MainActor
struct PaymentReturnTests {
    /// **只问一次等于没问。** 入账走 Stripe 的 webhook，有延迟。
    @Test func itAsksMoreThanOnce() {
        #expect(AccountService.paymentPollDelays.count >= 3,
                "切回来只问 \(AccountService.paymentPollDelays.count) 次 —— webhook 还没到账就放弃了")
    }

    /// **第一问必须是立刻。** 已经到账的那种情况不该让他多等一秒。
    @Test func theFirstAskIsImmediate() {
        #expect(AccountService.paymentPollDelays.first == 0)
    }

    /// **总跨度要盖得住 webhook 的延迟。**
    /// 等两三秒就放弃，和不等是一回事 —— 而"不等"正是这条 bug 本身。
    @Test func theWindowIsLongEnoughToMatter() {
        let total = AccountService.paymentPollDelays.reduce(0, +)
        #expect(total >= 15,
                "一共只等 \(total) 秒 —— 那个窗口盖不住 webhook，他还是会看到旧余额")
    }

    /// **窗口从"他回来"那一刻开始数，不是从"他点了充值"那一刻。**
    ///
    /// 我第一版直接 `waitUntilAppIsFrontmost()` —— 而他点"充值"那一刻
    /// app 本来就是前台的。浏览器没抢走焦点（另一个显示器、另一个 Space、
    /// 浏览器已经开在别处）时它**立刻返回**，整个窗口在他还没付款时就烧完了。
    ///
    /// 而我当时写的三条判据只验了间隔表本身 ——
    /// **它们绿着，而他回来看到的还是旧余额**（清单第 3 条）。
    ///
    /// 这一条盯着那一对：先等他走，再等他回来。
    @Test func theWindowStartsWhenHeComesBackNotWhenHeLeaves() throws {
        let src = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/PalmierPro/Account/AccountService.swift"),
            encoding: .utf8)
        guard let leave = src.range(of: "waitUntilAppResignsActive("),
              let back = src.range(of: "await waitUntilAppIsFrontmost()", range: leave.upperBound..<src.endIndex)
        else {
            Issue.record("付款回来那一段找不着了 —— 或者又变成只等一次前台")
            return
        }
        #expect(leave.upperBound < back.lowerBound,
                "先等前台再等离开 —— 那等于没等：他点充值时 app 就是前台的")
    }

    /// **等不到"他离开"也不许卡死。** 浏览器可能开在另一个显示器上，
    /// 焦点根本不动 —— 那时照常去问余额，而不是永远等下去。
    @Test @MainActor func notLeavingIsNotAFailure() async {
        await waitUntilAppResignsActive(timeout: .milliseconds(50))
    }

    /// 间隔要**越等越久**，不是死循环轮询：前面密、后面疏。
    @Test func theIntervalsBackOff() {
        let d = AccountService.paymentPollDelays
        #expect(zip(d.dropFirst(), d).allSatisfy { $0 >= $1 },
                "间隔是 \(d) —— 没有退避，要么打爆接口，要么等不够久")
    }
}
