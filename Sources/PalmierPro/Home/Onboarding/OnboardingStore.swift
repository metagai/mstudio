import Foundation
import Observation

@MainActor @Observable
final class OnboardingStore {
    /// Inherited from the pre-survey welcome overlay so existing installs stay onboarded.
    static let completionKey = "hasSeenWelcome"
    static let shared = OnboardingStore()

    private static let surveyVersion = 2

    private(set) var step = OnboardingStep.account

    /// 直接落到某一步 —— **给取景器用**。
    ///
    /// 引导一共四屏，而此前只有第一屏可能被人看过：要看第四屏得先答完问卷。
    /// 2026-09-02 创始人装完真机截了一张，四个登录按钮的字**全竖排了** ——
    /// 那一屏是新用户看到的第一样东西，而没有任何人看过它。
    func jumpForTesting(to step: OnboardingStep) { self.step = step }
    private(set) var isComplete: Bool
    private(set) var selections: [OnboardingQuestion: Set<String>] = [:]
    private(set) var sampleState: OnboardingSampleState = .idle

    private let defaults: UserDefaults
    private var didCaptureSurvey = false
    private var sampleTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isComplete = defaults.bool(forKey: Self.completionKey)
    }

    func advance() {
        move(by: 1)
    }

    func goBack() {
        move(by: -1)
    }

    /// Reports the survey once, no matter how often the user steps back.
    func submitSurvey() {
        if !didCaptureSurvey {
            didCaptureSurvey = true
            Analytics.capture(.onboardingCompleted, properties: [
                "survey_version": Self.surveyVersion,
                "roles": selection(for: .roles).sorted(),
                "video_types": selection(for: .videoTypes).sorted(),
                "interests": selection(for: .interests).sorted(),
                "acquisition_source": selection(for: .acquisitionSource).sorted().first ?? "not_provided",
                "previous_editors": selection(for: .previousEditors).sorted(),
            ])
        }
        advance()
    }

    /// 这一屏上有没有那条"以后再说"的出路。
    ///
    /// **一登录它就消失了** —— 上一版的条件带着 `!isSignedIn`。
    /// 于是登录之后主按钮只剩"教程"，而示例工程下载失败时
    /// `complete()` 不会被调用：**他被锁在一张关不掉的卡里，而网络抖一下就会发生。**
    ///
    /// 抽出来是为了让判据能直接问它 —— 那个条件长在 View 里，判据够不着。
    nonisolated static func showsSkip(step: OnboardingStep, signedIn: Bool, misconfigured: Bool) -> Bool {
        step == .account
    }

    func complete() {
        defaults.set(true, forKey: Self.completionKey)
        isComplete = true
    }

    func skip() {
        sampleTask?.cancel()
        sampleTask = nil
        sampleState = .idle
        complete()
    }

    func selection(for question: OnboardingQuestion) -> Set<String> {
        selections[question, default: []]
    }

    func toggle(_ option: OnboardingOption, for question: OnboardingQuestion) {
        var selection = selection(for: question)

        if !question.allowsMultipleSelection {
            selections[question] = selection.contains(option.id) ? [] : [option.id]
            return
        }

        if question.exclusiveOptionIDs.contains(option.id) {
            selections[question] = selection == [option.id] ? [] : [option.id]
            return
        }

        selection.subtract(question.exclusiveOptionIDs)
        if selection.contains(option.id) {
            selection.remove(option.id)
        } else {
            selection.insert(option.id)
        }
        selections[question] = selection
    }

    /// Owned here rather than by the overlay so onboarding still completes once Home is torn down.
    func openSampleProject() {
        guard sampleTask == nil else { return }
        sampleState = .loading
        sampleTask = Task {
            defer { sampleTask = nil }
            do {
                guard let sample = try await SampleProjectService.shared.fetchSamples().first else {
                    sampleState = .failed
                    return
                }
                try Task.checkCancellation()
                try await AppState.shared.openSample(slug: sample.slug, startTutorial: true)
                try Task.checkCancellation()
                complete()
            } catch is CancellationError {
                sampleState = .idle
            } catch {
                Log.app.error("onboarding sample failed to open: \(error.localizedDescription)")
                sampleState = .failed
            }
        }
    }

    private func move(by offset: Int) {
        guard let destination = OnboardingStep(rawValue: step.rawValue + offset) else {
            // **往前走出最后一屏 = 引导结束。**
            //
            // 上一版这里直接 `return`：`submitSurvey()` → `advance()` →
            // `OnboardingStep(rawValue: 4)` → nil → 什么都不发生，
            // 而 `complete()` 在这条路上一次都不会被调用。
            //
            // 覆盖层由 `!isComplete` 驱动、开着命中测试、没有 Esc、没有关闭按钮，
            // `isComplete` 又没写进 UserDefaults —— **答完问卷按下 Continue 的人，
            // 退出重开还是这一屏，永远看不到那个输入框，也就永远打不出第一行字。**
            //
            // 而 `OnboardingStoreTests.stepsClampAtBothEnds` 把这个死锁
            // 当成"问卷是最后一屏"钉住了：**一条判据为一个死锁作了证。**
            if offset > 0 { complete() }
            return
        }
        step = destination
    }
}
