import Foundation
import Testing
@testable import PalmierPro

/// **第一屏那颗主按钮要真的把他放进产品里。**
///
/// 加它的那次提交（`f46e8489`，8/31）的信息写着
/// 「1112 个人落地，0 个人打过一行字」—— 它就是为了修这件事。
/// 而它自己的实现里多发了一条 `.metagStartDraft`：那条通知只有编辑器里的
/// 素材面板在听，**首次打开时编辑器还不存在**。
/// 于是这颗按钮除了关掉引导层什么都没做，而**没有任何判据在看它**。
@Suite("引导的出路")
@MainActor
struct OnboardingExitTests {

    private func store() -> OnboardingStore {
        OnboardingStore(defaults: UserDefaults(suiteName: "onboarding-\(UUID().uuidString)")!)
    }

    /// 「先看一眼你的片子」= 引导结束。**不是往下一步走。**
    @Test func theWayInEndsOnboarding() {
        let s = store()
        #expect(!s.isComplete)
        s.skip()
        #expect(s.isComplete, "按了主按钮引导还没结束 —— 他被留在卡里")
    }

    /// **出路只在第一屏上。**
    /// 后面两屏是问卷，那里不该有"以后再说"——他已经在里面了。
    @Test func theExitLivesOnTheFirstScreenOnly() {
        #expect(OnboardingStore.showsSkip(step: .account, signedIn: false, misconfigured: false))
        #expect(!OnboardingStore.showsSkip(step: .discovery, signedIn: false, misconfigured: false))
        #expect(!OnboardingStore.showsSkip(step: .profile, signedIn: false, misconfigured: false))
    }

    /// **登录了也不该被锁住。**
    /// 上一版这个条件带着 `!isSignedIn`，于是登录之后出路消失，
    /// 而示例工程下载失败时 `complete()` 不会被调用 —— 一张关不掉的卡。
    @Test func signingInDoesNotTakeTheExitAway() {
        #expect(OnboardingStore.showsSkip(step: .account, signedIn: true, misconfigured: false))
        #expect(OnboardingStore.showsSkip(step: .account, signedIn: false, misconfigured: true))
    }
}
