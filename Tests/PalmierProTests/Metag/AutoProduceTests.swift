import Foundation
import Testing
@testable import PalmierPro

/// **草案好了就自己往下走 —— 但花的是他的钱。**
///
/// 2026-09-15 创始人撤销了「花钱那一步永不自动」，换成**按钮标价即同意**。
/// 「标价」是这条规矩的全部重量：报不出准价就不算标过价，也就不许自动。
/// 混档的那个数不是真的（只有口播镜用高档、其余回落 local），所以它是 nil。
@Suite("自动出片的闸")
struct AutoProduceTests {
    private func decide(
        stopped: Bool = false, alreadyCounting: Bool = false, ready: Bool = true,
        blocked: Bool = false, signedIn: Bool = true, exactPrice: Int? = 8
    ) -> Bool {
        MetagDraftSheet.shouldAutoProduce(
            stopped: stopped, alreadyCounting: alreadyCounting, ready: ready,
            blocked: blocked, signedIn: signedIn, exactPrice: exactPrice)
    }

    @Test func itStartsWhenTheDraftIsReadyAndThePriceIsExact() {
        #expect(decide())
    }

    /// 他按过「停下」之后就再也不自动 —— 说过一次不要，不该再被问第二次。
    @Test func itNeverRestartsAfterHeStoppedIt() {
        #expect(!decide(stopped: true))
    }

    /// 报不出准价 = 没标价 = 没同意。
    @Test func itRefusesWithoutAnExactPrice() {
        #expect(!decide(exactPrice: nil))
    }

    /// 访客付不了钱：自动只会把他推到一句失败上。
    @Test func itRefusesForGuests() {
        #expect(!decide(signedIn: false))
    }

    /// 档位坏了点下去是 503，自动等于替他撞墙。
    @Test func itRefusesWhenTheEngineIsDown() {
        #expect(!decide(blocked: true))
    }

    /// 草案还没好，没有可付的东西。
    @Test func itWaitsForTheDraft() {
        #expect(!decide(ready: false))
    }

    /// 倒计时已经在跑 —— 再起一个会让两条都去扣费。
    @Test func itDoesNotStartTwice() {
        #expect(!decide(alreadyCounting: true))
    }
}
