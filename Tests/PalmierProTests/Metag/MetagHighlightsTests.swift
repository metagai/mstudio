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
