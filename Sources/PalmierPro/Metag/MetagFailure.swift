import Foundation

/// 失败的**种类** —— 三种失败要说的话完全不一样，说错一种比不说更糟。
///
/// 分类在网关那侧做（`workers/failure.py`，拿真实上游报错原文分类、变异验证过），
/// 我们只负责把它翻译成一句人话和一条下一步。
///
/// **Mac 此前一句都没用上**：`error_kind` 一直在响应里，而客户端从没解过它，
/// 于是三种失败共用一句「换个说法再试」—— 那是给内容判回的话。
/// 对着一次上游 503 说这句，他会去改一句根本没问题的话、改完再失败一次，
/// **我们把自己的故障算在了他头上**。
enum MetagFailureKind: String, CaseIterable, Sendable {
    /// 上游挂了，或者我们欠费。**不是他的问题** —— 让他再来。
    case upstream
    /// 内容被判回。**让他改**，不是让他等。
    case moderation
    /// 我们自己的 bug，或者分不出来。**让他别白等。**
    case unknown

    /// 拿不准就 `unknown` —— 「我们看到了」这句在任何情况下都不算撒谎。
    init(_ raw: String?) {
        self = MetagFailureKind(rawValue: raw ?? "") ?? .unknown
    }

    /// 这一种该跟他说什么。**每一句都带下一步。**
    ///
    /// ## 关于钱的那半句，必须由事实决定
    ///
    /// 上一版 `.upstream` 无条件说「没扣你钱」—— 而网关那侧明确存在
    /// 「退款三次全失败、打一行 `REFUND FAILED (owed)` 就走」的分支：
    /// 那时 `refunded=false`，**我们照样在告诉他没扣钱**。
    /// 而 `Job.refunded` 一直解出来了，它的注释自己写着
    /// 「用户在出事那一刻最想知道这个」，然后没人用它。
    ///
    /// `.moderation` / `.unknown` 更干脆：**一个字都不提钱** ——
    /// 他刚花掉 180 credits、片子没了，界面说"换个说法再试"。
    ///
    /// **关于钱，宁可说"我在查"，绝不能说错。**
    /// `refunded` 为 nil（网关没说）时也走"正在核对"那一支 —— 不猜。
    @MainActor func message(refunded: Bool?) -> String {
        let money = refunded == true
            ? L10n.string("The credits are back in your balance.")
            : L10n.string("We're checking the credits for this one — any refund shows up in credit activity.")
        return "\(headline) \(money)"
    }

    @MainActor private var headline: String {
        switch self {
        case .upstream:
            L10n.string("Our side had trouble making this one — try again in a few minutes.")
        case .moderation:
            L10n.string("This one couldn't be filmed as written. Try describing the scene a different way.")
        case .unknown:
            L10n.string("This one didn't come out. We can see it on our side — try again, or change a line.")
        }
    }
}
