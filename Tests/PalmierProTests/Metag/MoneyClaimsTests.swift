import Foundation
import Testing
@testable import PalmierPro

/// **关于钱，宁可说"我在查"，绝不能说错。**
///
/// 2026-09-02 走查在三处查到同一个形状：**我们在断言一件自己不知道的事。**
///
/// - `MetagFailureKind.upstream` 无条件说「没扣你钱」—— 而网关那侧明确存在
///   「退款三次全失败、打一行 `REFUND FAILED (owed)` 就走」的分支，
///   那时 `refunded=false`，我们照样在告诉他没扣钱。
/// - `MetagReshoot` 在四条路上说「没扣你钱」，其中两条是
///   **钱已经花掉、货也做出来了**（下载失败、他中途删了那个 clip）。
/// - 而 `Job.refunded` 一直解出来了，注释写着「用户在出事那一刻最想知道这个」，
///   然后没人用它。
///
/// **主动断言错的，比不说更糟** —— 他随后在流水里看到一笔扣款。
@Suite("关于钱的断言")
@MainActor
struct MoneyClaimsTests {
    /// 退了才说退了。
    @Test func itSaysRefundedOnlyWhenItKnows() {
        let sure = MetagFailureKind.upstream.message(refunded: true)
        #expect(sure.contains(L10n.string("The credits are back in your balance.")))
    }

    /// **不知道就说在查** —— `false` 和 `nil` 走同一支，因为两者都不是"没扣"。
    @Test(arguments: [false, Bool?.none])
    func itNeverClaimsNotChargedWhenItCannotKnow(refunded: Bool?) {
        let text = MetagFailureKind.upstream.message(refunded: refunded)
        #expect(text.contains(L10n.string("We're checking the credits for this one — any refund shows up in credit activity.")),
                "退款状态是 \(String(describing: refunded)) 时说的是：\(text)")
        #expect(!text.contains(L10n.string("The credits are back in your balance.")))
    }

    /// **三种失败都要提钱。** 上一版 `.moderation` / `.unknown` 一个字都不提 ——
    /// 他刚花掉 180 credits、片子没了，界面说"换个说法再试"。
    @Test(arguments: [MetagFailureKind.upstream, .moderation, .unknown])
    func everyFailureSaysSomethingAboutTheMoney(kind: MetagFailureKind) {
        let text = kind.message(refunded: nil)
        #expect(text.contains(L10n.string("We're checking the credits for this one — any refund shows up in credit activity.")),
                "\(kind) 那一句一个字都没提钱：\(text)")
    }

}
