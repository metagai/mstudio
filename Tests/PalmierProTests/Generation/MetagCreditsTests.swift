import Testing
@testable import PalmierPro

/// 额度流水的文案。
///
/// 2026-08-01 的事故里我们弄丢了一位新用户付过钱的成片，退了额度、重出了一版 ——
/// 而他在产品里没有任何地方能看到这件事发生过，只知道"四个 credits 花掉、片子全部失败"。
///
/// 守的是**说实话**：退款要说清楚为什么退。只写"退款"等于没说，
/// 而"系统原因"是推卸 —— 是我们把它弄丢了。
@Suite("额度流水文案")
struct MetagCreditsTests {
    private func entry(_ reason: String, _ delta: Int) -> MetagGateway.CreditEntry {
        .init(at: 1_785_570_000, reason: reason, delta: delta, job_id: nil, title: nil)
    }

    @Test("弄丢成片的退款要承认是我们弄丢的")
    func admitsFault() {
        let d = MetagCreditsView.describe(entry("refund_lost_artifact", 4))
        #expect(d.label.contains("弄丢"))
        #expect(d.isRefund)
    }

    @Test("补偿性重出要说清楚是我们出的钱")
    func saysWhoPaid() {
        #expect(MetagCreditsView.describe(entry("refund_incident_regen", 4)).label.contains("我们承担"))
    }

    @Test("三种退款文案互不相同 —— 相同就等于没解释")
    func distinctReasons() {
        let labels = ["refund_failed", "refund_lost_artifact", "refund_incident_regen"]
            .map { MetagCreditsView.describe(entry($0, 4)).label }
        #expect(Set(labels).count == labels.count)
    }

    @Test("认不出的理由原样显示，不假装看得懂")
    func unknownPassthrough() {
        #expect(MetagCreditsView.describe(entry("something_new", -2)).label == "something_new")
    }
}
