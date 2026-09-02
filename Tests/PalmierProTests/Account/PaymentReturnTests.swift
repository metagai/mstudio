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

    /// 间隔要**越等越久**，不是死循环轮询：前面密、后面疏。
    @Test func theIntervalsBackOff() {
        let d = AccountService.paymentPollDelays
        #expect(zip(d.dropFirst(), d).allSatisfy { $0 >= $1 },
                "间隔是 \(d) —— 没有退避，要么打爆接口，要么等不够久")
    }
}
