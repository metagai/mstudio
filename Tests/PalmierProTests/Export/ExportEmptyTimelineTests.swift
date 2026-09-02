import Foundation
import Testing
@testable import PalmierPro

/// **空时间线上没得导。**
///
/// 2026-09-02 把导出面板渲成图第一次看见：左下角写着 **「~Zero KB」**
/// （`ByteCountFormatter` 对 0 字节吐 "Zero KB"，前面还被加了个波浪号），
/// 而「导出」那颗按钮**照样能按** —— 按下去导出一条 0 帧的片子，
/// 长得跟一次正常操作一模一样。
@Suite("导出：没得导的时候")
struct ExportEmptyTimelineTests {
    /// 0 字节不说话。**说不出数字就别说** —— 一个机器词比不说更糟。
    @Test(arguments: [Int64(0), -1])
    func nothingToSayAboutNothing(bytes: Int64) {
        #expect(ExportView.approximateSize(bytes).isEmpty,
                "空的时候屏幕上写着「\(ExportView.approximateSize(bytes))」")
    }

    /// 有东西的时候照常说，而且带波浪号 —— 那是**估算**，不是承诺。
    @Test func aRealSizeIsStillApproximate() {
        let text = ExportView.approximateSize(240_000_000)
        #expect(text.hasPrefix("~"), "估算值说成了确定值：\(text)")
        #expect(text.count > 2)
    }

    /// 那颗按钮在空时间线上必须是灰的。
    @Test func theExportButtonIsOffWhenThereIsNothing() throws {
        let src = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/PalmierPro/Export/ExportView.swift"),
            encoding: .utf8
        )
        #expect(src.contains(".disabled(exportTimeline.totalFrames <= 0)"),
                "空时间线上又能按导出了 —— 按下去是一条 0 帧的片子")
        // 主按钮全产品只有一种长相。这颗原来是没上 tint 的 `.glassProminent`，
        // 落成系统蓝，是全产品唯一一颗蓝的。
        #expect(src.contains(".buttonStyle(.capsule(.prominent, size: .regular))"))
    }
}
