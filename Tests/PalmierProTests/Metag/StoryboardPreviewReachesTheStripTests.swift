import Foundation
import Testing
@testable import PalmierPro

/// 分镜是一句一句写出来的，而 `shots` 要等整步跑完才有。
///
/// 网关的 `delivery.rs` 里那条判据点名的就是我们：
/// 「macOS 端（只轮询 REST、不连 WS）的用户在那 60 多秒里一个字都看不到」。
/// **REST 早就把 `storyboard_preview` 交出来了，Mac 一直没解这个字段。**
///
/// 幕布怎么画那几句，`theWaitShowsHisStoryNotSlotNumbers` 已经用像素判过了。
/// 这里守的是它上游那一段：**这几句话有没有走到幕布手上。**
@Suite("分镜边写边露")
struct StoryboardPreviewReachesTheStripTests {

    @MainActor
    private func model(_ json: String) throws -> MetagDraftModel {
        let m = MetagDraftModel()
        m.applyJobForTesting(try JSONDecoder().decode(MetagGateway.Job.self, from: Data(json.utf8)))
        return m
    }

    /// 分镜写到第二句，`shots` 还是空的 —— 他该看见那两句。
    @MainActor @Test func showsTheLinesWhileTheStoryboardIsStillBeingWritten() throws {
        let m = try model("""
        {"job_id":"j","status":"running","error":null,"shots":[],"cover":null,
         "storyboard_preview":["天亮之前，城市还没醒。","第一盏灯亮起来了。"]}
        """)
        #expect(m.narrations == ["天亮之前，城市还没醒。", "第一盏灯亮起来了。"])
    }

    /// 落定之后以 `shots` 为准：它是这条片子最终的那一份。
    /// **两份都在的时候取错一份，用户会看到跟成片对不上的字。**
    @MainActor @Test func prefersTheSettledShotsOnceTheyArrive() throws {
        let m = try model("""
        {"job_id":"j","status":"done","error":null,"cover":null,
         "storyboard_preview":["草稿一","草稿二"],
         "shots":[{"narration":"定稿一","video":"a.mp4","audio":"a.wav"},
                  {"narration":"定稿二","video":"b.mp4","audio":"b.wav"}]}
        """)
        #expect(m.narrations == ["定稿一", "定稿二"])
    }

    /// 老网关不发这个字段。**少一个字段不能让任务解析不出来。**
    @MainActor @Test func staysQuietWhenTheGatewayDoesNotSendIt() throws {
        let m = try model("""
        {"job_id":"j","status":"running","error":null,"shots":[],"cover":null}
        """)
        #expect(m.narrations.isEmpty)
    }
}
