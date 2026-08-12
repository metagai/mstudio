import Testing
@testable import PalmierPro

/// 额度流水的文案。
///
/// 2026-08-01 的事故里我们弄丢了一位新用户付过钱的成片，退了额度、重出了一版 ——
/// 而他在产品里没有任何地方能看到这件事发生过，只知道"四个 credits 花掉、片子全部失败"。
///
/// 守的是**说实话**：退款要说清楚为什么退。只写"退款"等于没说，
/// 而"系统原因"是推卸 —— 是我们把它弄丢了。
///
/// 断言不看具体某种语言的字样。这些文案 2026-08-12 改成走 `L()` 之后，
/// 测试跑在哪个语言包下取决于跑测试的那台机器 ——
/// **按中文子串断言的测试会在英文机器上红，而它守的东西一点没变。**
/// 判据因此落在语言无关的性质上：三种退款互不相同、都不等于裸理由、
/// 认不出的理由原样透出。语言覆盖由 `MetagCreditsCopyTests` 单独守。
@Suite("额度流水文案")
@MainActor
struct MetagCreditsTests {
    private func entry(_ reason: String, _ delta: Int) -> MetagGateway.CreditEntry {
        .init(at: 1_785_570_000, reason: reason, delta: delta, job_id: nil, title: nil)
    }

    @Test("退款要被认出来是退款")
    func marksRefunds() {
        for reason in ["refund", "refund_failed", "refund_lost_artifact",
                       "refund_incident_regen", "refund:whatever"] {
            #expect(MetagCreditsView.describe(entry(reason, 4)).isRefund, "\(reason)")
        }
    }

    @Test("三种退款文案互不相同 —— 相同就等于没解释")
    func distinctReasons() {
        let labels = ["refund_failed", "refund_lost_artifact", "refund_incident_regen"]
            .map { MetagCreditsView.describe(entry($0, 4)).label }
        #expect(Set(labels).count == labels.count)
    }

    @Test("每一种已知理由都被翻译过 —— 界面上不许出现原始理由字符串")
    func knownReasonsAreExplained() {
        for reason in ["signup", "purchase", "refund", "refund_failed", "refund_lost_artifact",
                       "refund_incident_regen", "generate", "vision_plan", "image_edit",
                       "voice_clone", "voice_tts", "refund:step"] {
            #expect(MetagCreditsView.describe(entry(reason, 4)).label != reason, "\(reason) 没被解释")
        }
    }

    @Test("认不出的理由原样显示，不假装看得懂")
    func unknownPassthrough() {
        #expect(MetagCreditsView.describe(entry("something_new", -2)).label == "something_new")
    }
}
