import Foundation
import Testing
@testable import PalmierPro

/// **等第一张画面的那段，别自己再加几秒。**
///
/// 2026-09-02 合伙人问：Mac 走 WS 还是轮询。查实：**一行 WebSocket 都没有**，
/// 每 4 秒一轮。加上从国内打过去实测 1.0–1.5 秒的来回，一轮实际约 5.2 秒。
///
/// 网关那侧首帧约第 13 秒就绪 —— 而轮询点落在 0 / 5.2 / 10.4 / 15.6：
/// **他第 15.6 秒才知道，下载完约第 17.4 秒才看见**。
/// 白丢 2.6 秒，最坏 5.2 秒。跟模型快不快无关，是我们自己的架构损耗。
///
/// 而这段等待里，第一张画面是唯一能救场的东西。
@Suite("草案轮询的节奏")
struct DraftPollCadenceTests {
    /// 还没有任何一张画面 —— 追紧。
    @Test func itChasesTheFirstFrame() {
        let interval = MetagDraftModel.pollInterval(hasFrame: false)
        #expect(interval < .seconds(2),
                "还在等第一张画面就已经 \(interval) 一轮了 —— 那几秒全是白等")
    }

    /// 画面到了 —— 退回去。**追紧只为救那一刻**，
    /// 整场都追是拿网关的负载换一个已经拿到的东西。
    @Test func itBacksOffOnceSomethingIsOnScreen() {
        #expect(MetagDraftModel.pollInterval(hasFrame: true) >= .seconds(4))
    }

    /// **首帧就绪到他看见，不许再超过一轮多。**
    ///
    /// 这一条是那两条的合起来说：拿真实来回时间和真实就绪点算一遍，
    /// 而不是只比两个常数的大小。
    @Test func theFirstFrameLandsWithoutAWastedGap() {
        let roundTrip = 1.2                       // 实测 1.04 / 1.04 / 1.49
        let readyAt = 13.0                        // 网关那侧首帧就绪
        let step = Double(MetagDraftModel.pollInterval(hasFrame: false)
            .components.seconds) + Double(MetagDraftModel.pollInterval(hasFrame: false)
            .components.attoseconds) / 1e18 + roundTrip
        var t = 0.0
        while t < readyAt { t += step }
        #expect(t - readyAt < 2.0,
                "首帧就绪之后还要再等 \(String(format: "%.1f", t - readyAt)) 秒才问得到 —— 这段等待里就这一张画面能救场")
    }
}
