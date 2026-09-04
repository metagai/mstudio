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
        #expect(OnboardingStep.account.rawValue == 0,
                "他看到的第一屏不是那个决定了 —— 前面又插了东西进来")
        #expect(OnboardingStep.account.rawValue < OnboardingStep.discovery.rawValue,
                "问卷又排到看片前面了 —— 那两屏正好站在价值前面")
        #expect(OnboardingStep.account.rawValue < OnboardingStep.profile.rawValue)
    }

    /// **第一屏就是看片那一屏。**
    ///
    /// 2026-09-03 删掉了 `welcome`：那是一张盖住首屏的卡片，
    /// 上面是「欢迎使用 METAG」+ 一张图库蝴蝶照 + **和首屏一字不差的同一句话**
    /// （两处用的是同一个 `L10n.string(...)`），底下一颗「继续」。
    /// 新用户看到的第一样东西，不该是一张重复被它挡住那句话的卡片。
    @Test func theFirstScreenIsTheFilmScreen() {
        #expect(OnboardingStep(rawValue: 0) == .account)
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
