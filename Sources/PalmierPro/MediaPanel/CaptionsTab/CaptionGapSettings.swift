import Foundation

/// 字幕跨过短停顿时保持可见的阈值。
///
/// 来自上游 1d76782（Close short caption gaps），**按我们的形状重写**：
/// 那个提交把这项改动和 #429（云端转写 + trackIndex）捆在一起，
/// 而我们的立场是转写一律端侧且免费 —— 拆冲突比重写贵。
/// 这里只取纯时间轴计算的部分，不碰任何 provider / credits 逻辑。
///
/// 为什么需要：说话人换气会在两条字幕之间留下十几帧空档，
/// 字幕闪一下再出现，读起来比一直在更累。

struct CaptionGapSettings: Equatable, Sendable {
    static let maximumGapRange = 0.0...2.0
    static let `default` = CaptionGapSettings(uncheckedMaximumGapSeconds: 0.25)

    let maximumGapSeconds: Double

    init?(maximumGapSeconds: Double) {
        guard maximumGapSeconds.isFinite,
              Self.maximumGapRange.contains(maximumGapSeconds) else { return nil }
        self.init(uncheckedMaximumGapSeconds: maximumGapSeconds)
    }

    func maximumGapFrames(fps: Int) -> Int {
        guard fps > 0, maximumGapSeconds > 0 else { return 0 }
        let frames = (maximumGapSeconds * Double(fps)).rounded(.down)
        guard frames.isFinite else { return 0 }
        return frames >= Double(Int.max) ? Int.max : Int(frames)
    }

    private init(uncheckedMaximumGapSeconds: Double) {
        self.maximumGapSeconds = uncheckedMaximumGapSeconds
    }
}
