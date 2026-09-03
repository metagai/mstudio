import Foundation
import Testing
@testable import PalmierPro

/// **一个 0.4fps 的素材不该有能力让整个 app 退出。**
///
/// 2026-09-02 走查查出：首个视频的 `sourceFPS < 0.5`（延时摄影、单帧视频）时
/// `Int(rate.rounded())` 是 0，`applyTimelineSettings` 没有下限 ——
///
/// - 所有时间码同时变成 `00:00:00:00`（看上去像"工程是空的"）
/// - 检视器顶部的工程时长算出 `inf`，`Int(seconds.rounded())` **直接 trap，app 崩**
@Suite("坏掉的帧率")
@MainActor
struct BrokenFrameRateTests {
    /// 时间线的 fps 永远不许落到 0。
    @Test(arguments: [0, -1, -30])
    func theTimelineNeverAcceptsAZeroFrameRate(fps: Int) {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [])
        editor.applyTimelineSettings(fps: fps, width: 1920, height: 1080)
        #expect(editor.timeline.fps >= 1,
                "fps 被设成 \(editor.timeline.fps) —— 所有时间码会变成 00:00:00:00，而工程时长会算出 inf")
    }

    /// 正常的帧率照常生效 —— 钳制不是把所有值都改掉。
    @Test func aRealFrameRateStillApplies() {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [])
        editor.applyTimelineSettings(fps: 24, width: 1920, height: 1080)
        #expect(editor.timeline.fps == 24)
    }

    /// **换算那一步也要兜住。** 上游哪一处算出 inf/NaN，
    /// 都不该由"画一个时长"的那行代码来 trap。
    @Test func theClockNeverTrapsOnNonsense() {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [])
        editor.timeline.fps = 0
        // 这一句在修之前会走到 `secondsToFrame(_:fps: 0)`，
        // 而调用点拿它去除会得到 inf。
        #expect(editor.frame(atSeconds: 3) >= 0)
    }
}
