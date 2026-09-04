import AppKit
import SwiftUI
import Testing
@testable import PalmierPro

/// **不知道不是零，也不是"我们不卖了"。**
///
/// 这一族的形状和「关于钱的断言」是同一个：**我们把问不到的东西画成了事实。**
/// 三处都在账户这一屏上，而这一屏是这个产品唯一收钱的地方。
///
/// 前提不是边界：从国内打 `api.metag.ai` 一个来回实测 1.1–1.3 秒，
/// 抖一下、超时一次，是每天都在发生的事。
@Suite("问不到的时候屏幕上写什么")
@MainActor
struct UnknownIsNotZeroTests {
    /// 余额还没答上来的时候，不许写 0，更不许把它涂红。
    ///
    /// 红色在这一屏只有一个意思：你没钱了，出不了片。
    @Test func anUnknownBalanceIsNotADrainedOne() {
        #expect(CreditSummaryView.amount(credits: 0, known: false) != "0",
                "余额没问到，屏幕上写了个 0")
        #expect(CreditSummaryView.tone(credits: 0, known: false) == .unknown,
                "余额没问到，却按'余额为零'涂色 —— 那是在说他出不了片")
        // 真的是零的时候要照旧报警，别为了躲上面那条把警报也关了。
        #expect(CreditSummaryView.tone(credits: 0, known: true) == .empty)
        #expect(CreditSummaryView.tone(credits: 5, known: true) == .low)
        #expect(CreditSummaryView.tone(credits: 900, known: true) == .normal)
    }

    /// 登录之前、以及**任何一次失败的刷新之后**，余额都是"不知道"。
    ///
    /// 第一版这条在变异下**没红**：它先调 `signOut()`，而 `signOut` 明写着
    /// 把标记清掉 —— 于是它测的是登出，不是启动那一刻，
    /// 而启动那一刻正是用户每天都会遇到的那一次。
    /// 现在"不知道"由 `metagCredits: Int?` 自己表示，`nil` 就是没问到，
    /// 两格状态不会再各说各话。
    @Test func notAskedYetIsNotZero() async {
        let account = AccountService.shared
        await account.signOut()
        #expect(account.metagCredits == nil,
                "没问过就说自己知道 —— 那 0 会被当成真余额、涂成红色画出来")
        #expect(account.creditsKnown == false)
    }

    /// **报价单拉不到，付钱的按钮也必须画得出来。**
    ///
    /// 上一版是 `if let pack = account.creditPack`：`plans` 只在启动时拉一次，
    /// 失败就空着，于是这颗按钮**整个不画，一句话都不留** ——
    /// 他这一整个会话都没有地方付钱。而这是我们唯一的收入入口。
    ///
    /// 量的是**屏幕上有没有东西**，不是源码里那个 `if` 还在不在。
    @Test func theBuyButtonSurvivesAPricingOutage() throws {
        #expect(AccountService.shared.creditPack == nil,
                "这条判据的前提是报价单为空；不为空就没在测想测的东西")
        // **用仓库里那一份，不再手搓**（见 `ViewInk`）。
        let bitmap = try ViewInk.bitmap(of: CreditPackButton(), width: 240)
        let lit = ViewInk.litPixels(bitmap)
        #expect(lit > 500,
                "报价单没拉到，付钱的按钮只画出 \(lit) 个像素 —— 他这一会话找不到地方付钱")
    }
}
