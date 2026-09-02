import Foundation
import Testing
@testable import PalmierPro

/// **看片排在问卷前面。**
///
/// 原来的顺序是 `welcome → discovery → profile → account`：一个刚装完、
/// 什么都还没看到的人，要先答完**两屏问卷**，才走到"看你的片子"那一步。
///
/// 8/29 起 1112 个人落地、**0 个人打过一行字**。在人看到价值之前问他是做什么的，
/// 得到的就是 0 —— 而这两屏正好站在价值前面。
///
/// 换过来之后真正的效果是：**愿意动手的人一屏问卷都不会看到**
/// （"先看一眼"和登录都直接结束引导），问卷只留给那些看完介绍就是不动手的人。
/// 而那恰恰是"你从哪儿知道我们"最该问的一群 —— 他们来了又要走。
@Suite("引导页的顺序")
struct OnboardingOrderTests {
    /// 翻页完全由 raw value 决定，所以顺序就是这几个数。
    @Test func theFilmComesBeforeTheSurvey() {
        #expect(OnboardingStep.welcome.rawValue < OnboardingStep.account.rawValue,
                "欢迎必须在最前")
        #expect(OnboardingStep.account.rawValue < OnboardingStep.discovery.rawValue,
                "问卷又排到看片前面了 —— 那两屏正好站在价值前面")
        #expect(OnboardingStep.account.rawValue < OnboardingStep.profile.rawValue)
    }

    /// 中间不许插东西：欢迎的下一屏就是看片。
    @Test func nothingStandsBetweenWelcomeAndTheFilm() {
        #expect(OnboardingStep(rawValue: OnboardingStep.welcome.rawValue + 1) == .account)
    }

    /// 不动手的人要有一条往下走的路 —— 看片这一屏不再是最后一屏了。
    @Test func thereIsAWayPastTheFilmScreen() throws {
        let src = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/PalmierPro/Home/Onboarding/OnboardingOverlay.swift"),
            encoding: .utf8
        )
        #expect(src.contains("onboarding.step == .account"),
                "看片那一屏没有往下走的路了 —— 不动手的人会卡在这儿")
        #expect(src.contains("Not now"))
    }
}
