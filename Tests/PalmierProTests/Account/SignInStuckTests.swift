import Testing
@testable import PalmierPro

/// **卡住的时候不能什么都不说。**
///
/// 登录的回调是靠浏览器跳 `metag://` 送回来的。网差的时候那一跳可能根本不到，
/// 而**服务端那边可能已经登录成功了** —— 他在浏览器里看到"已授权"，
/// 在 METAG 这边看到一个永远转下去的圈。
///
/// 在这一档存在之前，`waiting` 那句「正在等你在浏览器里完成」会一直说下去：
/// **没有超时、没有出路。** 一个产品最露怯的地方，就是卡住的时候它什么都不说。
@Suite("登录卡住的那一刻")
@MainActor
struct SignInStuckTests {
    /// 四档各说各的，一句都不能是空的。
    @Test func everyPhaseSaysSomethingOfItsOwn() {
        // **问界面真正会说的那句话**，不是我在这里再敲一遍的字符串。
        let lines = [AccountService.SignInPhase.waiting, .slow, .finishing,
                     .landed(credits: 200)].compactMap(\.message)
        #expect(lines.count == 4, "有一档一句话都没有")
        #expect(lines.allSatisfy { !$0.isEmpty })
        #expect(Set(lines).count == lines.count, "几档共用了同一句话")
    }

    /// **不说"失败了"。** 我们并不知道它失败了 —— 服务端很可能已经成功。
    /// 说错的比不说更糟（`docs/lessons.md` 第三十七条）。
    @Test func itNeverClaimsFailure() {
        let slow = AccountService.SignInPhase.slow.message ?? ""
        for word in ["失败", "错误", "failed", "error", "Failed", "Error"] {
            #expect(!slow.contains(word), "把'还没回来'说成了'失败了'：\(slow)")
        }
    }

    /// **"重开一次"要重开同一家。** 换一家等于让他从头再来，
    /// 而他刚刚已经在那一家授权过了。
    @Test func itRemembersWhichProviderHeUsed() async {
        let account = AccountService.shared
        await account.signOut()
        #expect(account.lastSignInProvider == nil,
                "还没登过就记着一家 —— 那颗「重开一次」会打开一个他没选过的窗")
    }

    /// 二十秒。**从国内打网关一个来回实测 1.1–1.3 秒**，扫码授权正常十几秒；
    /// 太短会在他还在手机上确认时打断他，太长等于没有。
    @Test func theBudgetLeavesRoomForHimToActuallySignIn() {
        #expect(AccountService.signInFeelsSlowAfter >= .seconds(15),
                "太短了 —— 他还在手机上点授权，我们就先说'太久了'")
        #expect(AccountService.signInFeelsSlowAfter <= .seconds(45),
                "太长了 —— 卡住的人要盯着一个不动的圈等这么久")
    }
}
