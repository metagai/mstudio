import Testing
@testable import PalmierPro

/// 这些断言原来写死了英文原文，于是在中文系统上跑就红 —— 而红的不是文案，是测试自己
/// 依赖了开发机的系统语言（上游那套本地化认三十种语言并跟随系统，我们原来那套只认三种）。
///
/// 真正要守的不变量与语言无关：**单数和复数不能落在同一句话上，而且数字要出现在里面。**
/// 当初写这几条，就是因为 1 也被说成 "credits"。
@Suite("Cost estimator localization")
@MainActor
struct CostEstimatorLocalizationTests {
    @Test func singularAndPluralCopyDiffer() {
        #expect(CostEstimator.localizedEstimate(1) != CostEstimator.localizedEstimate(2))
        #expect(CostEstimator.localizedInsufficientCredits(1, remaining: 0)
                != CostEstimator.localizedInsufficientCredits(2, remaining: 0))
        #expect(CostEstimator.localizedRemainingCredits(1, remaining: 4)
                != CostEstimator.localizedRemainingCredits(2, remaining: 4))
        #expect(CostEstimator.localizedGenerateLabel(1) != CostEstimator.localizedGenerateLabel(2))
    }

    @Test func copyStatesTheFigure() {
        #expect(CostEstimator.localizedEstimate(7).contains("7"))
        #expect(CostEstimator.localizedInsufficientCredits(7, remaining: 3).contains("7"))
        #expect(CostEstimator.localizedInsufficientCredits(7, remaining: 3).contains("3"))
        #expect(CostEstimator.localizedGenerateLabel(7).contains("7"))
    }

    /// 负数和 0 都说成 0 —— 用户不该看到 "-2 credits used"。
    @Test(arguments: [-2, 0])
    func nonpositiveUsedCreditsDisplayAsZero(credits: Int) {
        #expect(CostEstimator.localizedUsedCredits(credits) == CostEstimator.localizedUsedCredits(0))
        #expect(CostEstimator.localizedUsedCredits(credits).contains("0"))
    }

    @Test func usedCreditsHandleSingularAndPlural() {
        #expect(CostEstimator.localizedUsedCredits(1) != CostEstimator.localizedUsedCredits(2))
        #expect(CostEstimator.localizedUsedCredits(1).contains("1"))
        #expect(CostEstimator.localizedUsedCredits(2).contains("2"))
    }
}
