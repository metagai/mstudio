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
        let starts = MetagFilmLayout.startSeconds(
            shotCount: 3, clipSeconds: [2.0, 1.0, 3.0],
            measured: { _ in Issue.record("有权威时长还去量文件"); return 1 }
        )
        #expect(starts == [0, 2, 3])
    }

    /// **拿不到就自己量，不要凭空假设等长。**
    @Test func withoutDurationsItMeasures() {
        let starts = MetagFilmLayout.startSeconds(
            shotCount: 3, clipSeconds: nil, measured: { _ in 1.5 }
        )
        #expect(starts == [0, 1.5, 3])
    }

    /// 清单比镜头短、或者某一段是 0 —— 那几段退回实测，**不整条作废**。
    @Test func aShortOrBrokenListFallsBackPerShot() {
        let starts = MetagFilmLayout.startSeconds(
            shotCount: 3, clipSeconds: [2.0, 0], measured: { _ in 0.5 }
        )
        #expect(starts == [0, 2, 2.5])
    }

    /// 一镜也是对的；零镜不该崩。
    @Test(arguments: [(0, [Double]()), (1, [0.0])])
    func edgesHold(count: Int, expected: [Double]) {
        #expect(MetagFilmLayout.startSeconds(
            shotCount: count, clipSeconds: nil, measured: { _ in 1 }
        ) == expected)
    }

    /// **旁白落在各自那一镜的起点。**
    ///
    /// 这一条问的是那个判断本身。**上一版问的是源码里那行字还在不在** ——
    /// 而把 `fps` 传成 0（两个源码字符串一字不改），每一段旁白都落到开头，
    /// 正是 web 端那次「多个音轨叠加」，而判据全绿。
    @Test func eachNarrationLandsOnItsOwnShot() {
        // 三镜，第二镜原生出声（没有旁白）。**按镜号配，不按位置配。**
        let placed = MetagFilmLayout.narrationFrames(
            shots: [0, 1, 2], narrations: [0, 2], starts: [0, 60, 90])
        #expect(placed.map(\.shot) == [0, 2], "把旁白配到了没有旁白的那一镜上")
        #expect(placed.map(\.frame) == [0, 90],
                "第三镜的旁白落在 \(placed.map(\.frame)) —— 它该落在自己那一镜的起点")
    }

    /// **不许全叠在开头。**
    @Test func narrationsNeverAllStackAtTheStart() {
        let starts = MetagFilmLayout.startSeconds(
            shotCount: 3, clipSeconds: [2, 2, 2], measured: { _ in 1 }).map { Int($0 * 30) }
        let placed = MetagFilmLayout.narrationFrames(
            shots: [0, 1, 2], narrations: [0, 1, 2], starts: starts)
        #expect(Set(placed.map(\.frame)).count == 3,
                "三段旁白落在 \(placed.map(\.frame)) —— 叠在一起了")
    }

    /// **那个能传错的参数已经不存在了。**
    ///
    /// 上一版 `startFrames` 收一个 `fps`；把它传成 0（源码字符串一字不改），
    /// 每一段旁白都落到开头 —— 正是 web 端那次「多个音轨叠加」——
    /// 而判据全绿。给它加下限只是把 [0,1,2] 变成 [0,2,4]，还是塌的。
    ///
    /// **判据看不见的错，就让它写不出来**：起点按秒算，
    /// 换算交给 `EditorViewModel.frame(atSeconds:)`，fps 从时间线自己读。
    @Test @MainActor func thereIsNoFpsToGetWrong() {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [])
        // 时间线自己的 fps 被弄坏时也不塌成一堆 —— 换算那一处兜了下限。
        editor.timeline.fps = 0
        let seconds = MetagFilmLayout.startSeconds(
            shotCount: 3, clipSeconds: [2, 2, 2], measured: { _ in 1 })
        let frames = seconds.map(editor.frame(atSeconds:))
        #expect(Set(frames).count == 3, "起点算出来是 \(frames) —— 三镜叠在一起了")
    }

    /// 剩下的仍然只能比源码：**"整件事是一步撤销"没有别的问法** ——
    /// 它是一个结构事实，不是一个可以算出来的值。
    @Test func theWholeFilmIsOneUndoStep() throws {
        let src = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/PalmierPro/Metag/MetagJobOpener.swift"),
            encoding: .utf8)
        #expect(src.contains("editor.undo.perform(L10n.string(\"Add Film\"))"),
                "铺片子变成好几步撤销了 —— 他做的是「打开一条片子」这一个动作")
        #expect(src.contains("MetagFilmLayout.narrationFrames("),
                "又自己在调用点算旁白落点了 —— 那一层没有判据看得见")
    }
}
