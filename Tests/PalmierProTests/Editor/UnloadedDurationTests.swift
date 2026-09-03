import Foundation
import Testing
@testable import PalmierPro

/// **元数据还没到的时候，一段素材不该变成一帧。**
///
/// 所有类型的 `duration` 都由异步的 `loadMetadata` 填 —— 图片也是
/// （它在那里被赋成 `Defaults.imageDurationSeconds`）。在它跑完之前
/// `duration` 一律是 0，而 `clipDurationFrames` 的 `max(1, ...)`
/// 会把它变成**一帧**。
///
/// **一帧宽的片段和"什么都没发生"在屏幕上分不出来。**
/// 而因为 duration 是被并发 Task 填的，实际会是
/// "有几段正常、有几段一帧"的随机组合 —— **比全错更难被当成 bug 上报。**
///
/// 2026-09-02：这一族一共三处（铺成片、拖素材进时间线、双击开 Source 预览），
/// 而我只修了第一处就以为修完了。
/// 产品技术负责人的规矩：**agent 报告里出现"同一个形状"时，
/// 把那一族全部列出来再动手，不按行号逐条改。**
@Suite("元数据还没到的时候")
@MainActor
struct UnloadedDurationTests {
    private func editor() -> EditorViewModel {
        let e = EditorViewModel()
        e.timeline = Fixtures.timeline(tracks: [])
        return e
    }

    /// 时长还没填上的素材，铺出来要**看得见、抓得住**。
    @Test func anAssetWithoutMetadataStillGetsAVisibleClip() {
        let e = editor()
        // loadMetadata 还没跑 —— 这就是 duration 的初值。
        let asset = MediaAsset(url: URL(fileURLWithPath: "/tmp/a.mp4"), type: .video, name: "a")
        let frames = e.clipDurationFrames(for: asset, segment: nil)
        #expect(frames > e.timeline.fps / 2,
                "铺出来只有 \(frames) 帧 —— 那和「什么都没发生」在屏幕上分不出来")
    }

    /// 真实时长照常生效 —— 兜底不是把所有片段都改成同一个长度。
    @Test func arealDurationStillWins() {
        let e = editor()
        let asset = MediaAsset(url: URL(fileURLWithPath: "/tmp/a.mp4"), type: .video,
                               name: "a", duration: 7)
        #expect(e.clipDurationFrames(for: asset, segment: nil) == 7 * e.timeline.fps)
    }

    /// 显式给了区间就用区间，兜底不许插队。
    @Test func anExplicitSegmentIsHonoured() {
        let e = editor()
        let asset = MediaAsset(url: URL(fileURLWithPath: "/tmp/a.mp4"), type: .video, name: "a")
        #expect(e.clipDurationFrames(for: asset, segment: 2...5) == 3 * e.timeline.fps)
    }
}
