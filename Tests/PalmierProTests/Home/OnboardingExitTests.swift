import Foundation
import Testing
@testable import PalmierPro

/// **登录之后，这张卡的出口消失了。**
///
/// 「以后再说」那颗的条件里带着 `!account.isSignedIn` ——
/// 他一登录它就没了，剩下的主按钮是"教程"，
/// 而 `openSampleProject` 失败时 `complete()` 不会被调用：
/// **他被锁在一张关不掉的卡里，而网络抖一下就会发生。**
///
/// 2026-09-02 上午我修了这一屏的另一个死锁（走出最后一屏时 `complete()`
/// 从不被调用），**而这一条走查报告里写着，我当时没管。**
/// 同一屏、同一类"人出不去"，我只修了一半。
@Suite("引导页的出口")
struct OnboardingExitTests {
    /// **登录与否，账号那一屏都得有一条出路。**
    @Test(arguments: [(true, false), (false, false), (true, true), (false, true)])
    func theAccountStepAlwaysHasAWayOut(signedIn: Bool, misconfigured: Bool) {
        #expect(OnboardingStore.showsSkip(step: .account,
                                          signedIn: signedIn, misconfigured: misconfigured),
                "登录=\(signedIn) 配置异常=\(misconfigured) 时那一屏没有出口")
    }

    /// 别的屏本来就有"继续"，不需要第二条出路 —— 出口不是到处都加。
    @Test(arguments: [OnboardingStep.welcome, .discovery, .profile])
    func theOtherStepsDoNotNeedOne(step: OnboardingStep) {
        #expect(!OnboardingStore.showsSkip(step: step, signedIn: false, misconfigured: false))
    }

    /// **走出最后一屏 = 引导结束**（上午那一条，一起守着，别再退回去）。
    @Test @MainActor func finishingTheSurveyEndsOnboarding() throws {
        let suite = try #require(UserDefaults(suiteName: "onb-exit-\(UUID().uuidString)"))
        defer { suite.removePersistentDomain(forName: suite.description) }
        let store = OnboardingStore(defaults: suite)
        for _ in 0..<5 { store.advance() }
        #expect(store.isComplete, "答完问卷按下 Continue 之后还留在那张关不掉的卡上")
    }
}
