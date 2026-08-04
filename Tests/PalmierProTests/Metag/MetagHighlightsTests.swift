import Foundation
import Testing

@testable import PalmierPro

/// 能量曲线抽稀。
///
/// 一分钟素材的包络是 24000 个点（hop 2.5ms），原样发给网关只是把一条
/// 跨太平洋的请求变慢 —— 它只拿这条曲线判断"哪里有劲"，不需要逐帧。
struct EnergyDownsampleTests {
    @Test func keepsShortSeriesUntouched() {
        let short: [Float] = [0.1, 0.2, 0.3]
        #expect(MetagGateway.downsample(short, to: 200) == short)
        #expect(MetagGateway.downsample(short, to: 3) == short)
    }

    @Test func hitsTheRequestedLength() {
        let long = (0..<24_000).map { Float($0) }
        #expect(MetagGateway.downsample(long, to: 200).count == 200)
    }

    /// 首尾都要覆盖到：只取前 200 个点的话，一分钟素材里我们只看了头 0.5 秒。
    @Test func spansTheWholeSeries() {
        let long = (0..<24_000).map { Float($0) }
        let out = MetagGateway.downsample(long, to: 200)
        #expect(out.first == 0)
        #expect(out.last ?? 0 > 23_000)
    }

    /// 边界值不能崩：0 长度、要 0 个点。
    @Test func survivesDegenerateInput() {
        #expect(MetagGateway.downsample([], to: 200).isEmpty)
        #expect(MetagGateway.downsample([1, 2, 3], to: 0) == [1, 2, 3])
    }
}

/// 亮点区间来自模型返回的 JSON —— **那是外部输入**。
/// 它直接构造 ClosedRange，而 `lower > upper` 是运行时崩溃，不是编译错误。
struct HighlightRangeTests {
    @Test func normalRangeSurvives() {
        let r = HighlightRange.clamp(start: 3, end: 9, duration: 60)
        #expect(r == 3...9)
    }

    @Test func clampsToTheAsset() {
        // 模型给的区间越界：收敛，而不是崩
        #expect(HighlightRange.clamp(start: -5, end: 9, duration: 60) == 0...9)
        #expect(HighlightRange.clamp(start: 50, end: 999, duration: 60) == 50...60)
    }

    @Test func rejectsWhatCannotBeACut() {
        // 倒置、零长、太短（铺上去看不见）、素材没时长、非有限数
        #expect(HighlightRange.clamp(start: 9, end: 3, duration: 60) == nil)
        #expect(HighlightRange.clamp(start: 5, end: 5, duration: 60) == nil)
        #expect(HighlightRange.clamp(start: 5, end: 5.05, duration: 60) == nil)
        #expect(HighlightRange.clamp(start: 0, end: 9, duration: 0) == nil)
        #expect(HighlightRange.clamp(start: .nan, end: 9, duration: 60) == nil)
        // 无穷**不是**"到结尾"，是一个坏响应。把坏数据悄悄解释成合理意图，
        // 正是错误输出的来源 —— 宁可不加这一段。
        #expect(HighlightRange.clamp(start: 0, end: .infinity, duration: 60) == nil)
    }
}
