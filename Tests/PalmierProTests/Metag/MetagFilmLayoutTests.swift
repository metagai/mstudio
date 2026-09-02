import Foundation
import Testing
@testable import PalmierPro

/// **他等了九十秒、付了 credits，拿到的是素材库里 N 个散文件和一条空时间线。**
///
/// `addMediaAsset` 只把素材加进库，从来不铺时间线；而片子落地这条路只调它。
/// 这个产品的承诺是"一句话变成一条片子"，交付的是一堆配料 ——
/// 他得自己把每一镜拖进去、排好序、再把旁白一条条对齐到各自那一镜。
///
/// 网关那侧早就为此准备好了 `shot_clips`：
/// 「一条压平的片子在时间线上只有一个色块……有了这份清单，
/// 编辑器铺的是 N 段可编辑素材。」
@Suite("片子铺到时间线上")
struct MetagFilmLayoutTests {
    /// 网关给的逐段时长是权威的 —— 30fps 下 2 秒就是 60 帧。
    @Test func startsComeFromTheGatewaysDurations() {
        let starts = MetagFilmLayout.startFrames(
            shotCount: 3, clipSeconds: [2.0, 1.0, 3.0], fps: 30,
            measured: { _ in Issue.record("有权威时长还去量文件"); return 1 }
        )
        #expect(starts == [0, 60, 90])
    }

    /// **拿不到就自己量，不要凭空假设等长。**
    @Test func withoutDurationsItMeasures() {
        let starts = MetagFilmLayout.startFrames(
            shotCount: 3, clipSeconds: nil, fps: 30, measured: { _ in 45 }
        )
        #expect(starts == [0, 45, 90])
    }

    /// 清单比镜头短、或者某一段是 0 —— 那几段退回实测，**不整条作废**。
    @Test func aShortOrBrokenListFallsBackPerShot() {
        let starts = MetagFilmLayout.startFrames(
            shotCount: 3, clipSeconds: [2.0, 0], fps: 30, measured: { _ in 15 }
        )
        #expect(starts == [0, 60, 75])
    }

    /// 一镜也是对的；零镜不该崩。
    @Test(arguments: [(0, [Int]()), (1, [0])])
    func edgesHold(count: Int, expected: [Int]) {
        #expect(MetagFilmLayout.startFrames(
            shotCount: count, clipSeconds: nil, fps: 30, measured: { _ in 10 }
        ) == expected)
    }

    /// **旁白对齐到各自那一镜的起点** —— 一段接一段挨着放会越走越偏。
    /// 这一条盯着落地那一步真的用了 `startFrames`，而不是顺次铺。
    @Test func narrationIsAlignedToItsOwnShot() throws {
        let src = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/PalmierPro/Metag/MetagJobOpener.swift"),
            encoding: .utf8
        )
        #expect(src.contains("MetagFilmLayout.startFrames("),
                "旁白又挨着铺了 —— 它比镜头短，第四镜的话会压在第三镜上")
        #expect(src.contains("startFrame: starts[slot]"))
        // **一步撤销**：他做的是"打开一条片子"这一个动作。
        #expect(src.contains("editor.undo.perform(L10n.string(\"Add Film\"))"),
                "铺片子变成好几步撤销了")
        // 复用 UI 那条域操作，不另写一套铺片逻辑。
        #expect(src.contains("editor.addClips(assets:"))
    }
}
