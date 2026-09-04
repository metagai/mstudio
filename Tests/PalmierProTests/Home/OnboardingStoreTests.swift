import Foundation
import Testing
@testable import PalmierPro

@Suite("Onboarding store")
@MainActor
struct OnboardingStoreTests {
    /// **第一屏就是他要做的那个决定。**
    ///
    /// 2026-09-03 删掉了 `welcome` 那一步：它是一张盖住首屏的卡片，
    /// 上面是「欢迎使用 METAG」+ 一张图库蝴蝶照 + **和首屏一字不差的同一句话**
    /// （两处用的是同一个 `L10n.string(...)`）。
    /// 新用户看到的第一样东西，不该是一张重复被它挡住那句话的卡片。
    @Test func newUserStartsAtTheDecision() throws {
        try withDefaults { defaults in
            let store = OnboardingStore(defaults: defaults)

            #expect(!store.isComplete)
            #expect(store.step == .account)
        }
    }

    @Test func existingWelcomeCompletionSkipsOnboarding() throws {
        try withDefaults { defaults in
            defaults.set(true, forKey: OnboardingStore.completionKey)

            let store = OnboardingStore(defaults: defaults)

            #expect(store.isComplete)
        }
    }

    /// **第一屏就是看片，不是问卷。**
    ///
    /// 2026-09-01 把顺序从 `welcome → discovery → profile → account`
    /// 换成 `welcome → account → discovery → profile`：一个刚装完、
    /// 什么都还没看到的人，原来要先答完两屏问卷才走到"看你的片子"。
    /// 2026-09-03 `welcome` 删掉之后，`account` 直接就是第一屏。
    @Test func theFirstScreenIsTheFilm() throws {
        try withDefaults { defaults in
            let store = OnboardingStore(defaults: defaults)

            #expect(store.step == .account)
        }
    }

    /// 不动手的人才走到问卷，而且它排在看片后面。
    @Test func theSurveyComesAfterTheFilm() throws {
        try withDefaults { defaults in
            let store = OnboardingStore(defaults: defaults)
            store.advance()

            #expect(store.step == .discovery)

            store.advance()
            #expect(store.step == .profile)
        }
    }

    @Test func stepsClampAtBothEnds() throws {
        try withDefaults { defaults in
            let store = OnboardingStore(defaults: defaults)
            store.goBack()

            #expect(store.step == .account)

            store.advance()
            store.advance()
            store.advance()
            store.advance()

            // **走出最后一屏 = 引导结束，不是原地不动。**
            //
            // 上一版这里断言的是 `step == .profile` —— 而那正是一个死锁：
            // `move(by:)` 的 guard 直接 return，`complete()` 永不调用，
            // 覆盖层永远关不掉，退出重开还是这一屏。
            // **这条判据当时为那个死锁作了证。**
            #expect(store.isComplete, "答完问卷按下 Continue 之后引导没结束 —— 他被锁在一个关不掉的框里")
        }
    }

    @Test func completionPersists() throws {
        try withDefaults { defaults in
            let store = OnboardingStore(defaults: defaults)
            store.advance()

            store.complete()

            #expect(store.isComplete)
            #expect(defaults.bool(forKey: OnboardingStore.completionKey))
            #expect(OnboardingStore(defaults: defaults).isComplete)
        }
    }

    @Test func selectingAnOptionAgainDeselectsIt() throws {
        try withDefaults { defaults in
            let store = OnboardingStore(defaults: defaults)
            store.toggle(.other, for: .videoTypes)
            store.toggle(.other, for: .videoTypes)

            #expect(store.selection(for: .videoTypes).isEmpty)
        }
    }

    @Test func acquisitionSourceIsSingleSelect() throws {
        try withDefaults { defaults in
            let store = OnboardingStore(defaults: defaults)
            let google = try #require(OnboardingQuestion.acquisitionSource.options.first { $0.id == "google" })
            let github = try #require(OnboardingQuestion.acquisitionSource.options.first { $0.id == "github" })

            store.toggle(google, for: .acquisitionSource)
            store.toggle(github, for: .acquisitionSource)

            #expect(store.selection(for: .acquisitionSource) == ["github"])
        }
    }

    @Test func noPreviousEditorIsExclusive() throws {
        try withDefaults { defaults in
            let store = OnboardingStore(defaults: defaults)
            let premiere = try #require(OnboardingQuestion.previousEditors.options.first { $0.id == "premiere_pro" })
            let none = try #require(OnboardingQuestion.previousEditors.options.first { $0.id == "none" })
            let capcut = try #require(OnboardingQuestion.previousEditors.options.first { $0.id == "capcut" })

            store.toggle(premiere, for: .previousEditors)
            store.toggle(none, for: .previousEditors)
            #expect(store.selection(for: .previousEditors) == ["none"])

            store.toggle(capcut, for: .previousEditors)
            #expect(store.selection(for: .previousEditors) == ["capcut"])
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "OnboardingStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }
}
