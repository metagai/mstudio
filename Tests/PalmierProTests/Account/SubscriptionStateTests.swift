import Foundation
import Testing
@testable import PalmierPro

/// **「他自己取消了」和「他的卡扣不动了」不能长得一样。**
///
/// `subscribed` 是个布尔，两件事在它里面完全同形 —— 而这两件事要他做的事
/// 完全相反：取消了什么都不用做（别让他以为已经断了），扣款失败要他去换卡
/// （且必须说清现在还没断，Stripe 还会重试两三周）。
@Suite("订阅状态")
@MainActor
struct SubscriptionStateTests {
    private static let day = 1_788_265_812   // 2026-08-31 前后的一个真日子

    @Test func cancellingKeepsTheDateSoWeCanSayUntilWhen() {
        let state = AccountService.state(until: Self.day, status: "canceling")
        #expect(state == .canceling(until: Date(timeIntervalSince1970: TimeInterval(Self.day))))
    }

    /// **扣款失败不是"已经断了"。** Stripe 还要重试两三周，
    /// 这段时间他该照常用 —— 说成断了会把一个还在用的人吓走。
    @Test func pastDueIsNotEnded() {
        #expect(AccountService.state(until: Self.day, status: "past_due") == .pastDue)
        #expect(AccountService.state(until: 0, status: "past_due") == .pastDue,
                "没有日期也仍然是 past_due —— 状态由 sub_status 说了算")
    }

    @Test func activeCarriesTheRenewalDate() {
        #expect(AccountService.state(until: Self.day, status: "active")
                == .active(until: Date(timeIntervalSince1970: TimeInterval(Self.day))))
    }

    /// 没订过的人这一行整个不出现 —— 不给他一句"你没有订阅"。
    @Test(arguments: [nil, "", "something_new"])
    func neverSubscribedShowsNothing(status: String?) {
        #expect(AccountService.state(until: 0, status: status) == .none)
    }

    /// **状态由 `sub_status` 说了算，日期只是补充。**
    /// 反过来推（"有日期就是订着"）会把"卡扣不动了"讲成"一切正常"。
    @Test func aDateAloneNeverMeansActive() {
        #expect(AccountService.state(until: Self.day, status: nil) == .none)
    }

    /// 取消了但日期丢了 —— 宁可说"已到期"，也不要说一个我们没有的日子。
    @Test func cancellingWithoutADateFallsBackToEnded() {
        #expect(AccountService.state(until: 0, status: "canceling") == .ended)
    }

    // MARK: - 那扇门不许是假的

    /// **管理入口必须有它自己的出现条件，不能挂在那一行里面。**
    ///
    /// 合伙人在 web 上栽过：管理按钮写在订阅那一行内部，而那一行为 nil 时
    /// 整段不渲染 —— 于是守着它的那个布尔一次都没起过作用，
    /// 变异把它改成恒真，四条判据全绿。**留着一个不做事的门，
    /// 下一个人会以为门在那儿。**
    ///
    /// 这条盯的是：`canManage` 在"没订过"和"订过"之间**真的会变**。
    @Test func theManageDoorActuallyOpensAndCloses() throws {
        let src = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/PalmierPro/Account/SubscriptionLine.swift"),
            encoding: .utf8
        )
        // 门必须在 `text` 那个可选值**外面** —— 在里面就等于没有门。
        let door = try #require(src.range(of: "if canManage {"))
        let line = try #require(src.range(of: "if let text {"))
        #expect(door.lowerBound > line.lowerBound)
        #expect(src.contains("case .none: false"),
                "没付过费的人也给了管理链接 —— 网关对他回 404")
    }
}
