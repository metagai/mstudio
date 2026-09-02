import Foundation
import Testing
@testable import PalmierPro

/// **打开一部已出的成片 —— 那是每一部片子唯一走的那条路，而它一条判据都没有。**
///
/// 2026-09-02 产品技术负责人在 web 那侧撞见这个形状：他们那条
/// 「没有 `shot_clips` 时行为不变」的判据，夹具带着 `preview`，
/// 于是走的是**回退路**；而**打开一部成片**（无 preview、有 N 个
/// `shots[].video`、无 `shot_clips`）那条路，一条判据都没覆盖。
///
/// Mac 这侧更彻底：整段落地逻辑散在 `MetagJobOpener.open()` 里 ——
/// 要网络、要编辑器、要真下载，**判据够不着**，于是只有几条
/// "源码里那行还在吗"的断言。
///
/// 而他又查出 `shot_clips` 在成片那条路上**从来没写过**。
/// 两件事叠起来：**在我们两个修完之前，无 `shot_clips` 就是每一部片子的常态。**
///
/// 这一组喂真 JSON、走真解码、问那份铺法。
@Suite("打开一部成片")
struct OpenFinishedFilmTests {
    /// 网关真实回的那个形状。默认**不带** `shot_clips` —— 那是常态，不是异常。
    private func job(shotCount: Int, shotClips: String? = nil, gain: String = "") throws
        -> MetagGateway.Job {
        let shots = (0..<shotCount)
            .map { #"{"narration":"第\#($0)句","video":"shot_\#($0).mp4","audio":"nar_\#($0).mp3"}"# }
            .joined(separator: ",")
        let json = """
        {"job_id":"j1","status":"done","shots":[\(shots)]\(shotClips ?? "")\(gain)}
        """
        return try JSONDecoder().decode(MetagGateway.Job.self, from: Data(json.utf8))
    }

    private func plan(_ job: MetagGateway.Job, measured: @escaping (Int) -> Double,
                      fps: Int = 30) -> MetagFilmLayout.Plan {
        MetagFilmLayout.plan(
            shotIndices: Array(job.shots.indices),
            narrationIndices: Set(job.shots.indices),
            clipSeconds: job.shot_clips?.map(\.seconds),
            masterGainDB: job.master_gain_db,
            measured: measured,
            frame: { Int($0 * Double(fps)) }
        )
    }

    /// **没有 `shot_clips` 的成片 —— 每一镜必须真的分得开。**
    ///
    /// 断言的不是"起始帧互不相同"（0.04 秒也互不相同，而 30fps 下那是
    /// 第 0/1/2/4 帧，用户看到的仍然是全叠在一起），是**至少一秒**。
    @Test func aFinishedFilmWithoutClipListStillSeparates() throws {
        let p = plan(try job(shotCount: 5), measured: { _ in 3.2 })
        let gaps = zip(p.shotStarts.dropFirst(), p.shotStarts).map(-)
        #expect(gaps.allSatisfy { $0 >= 30 },
                "五镜铺在 \(p.shotStarts) —— 30fps 下它们叠在一起，他打开看到的像什么都没发生")
        #expect(p.narrations.count == 5, "旁白少了 \(5 - p.narrations.count) 段")
    }

    /// 每一段旁白落在**自己那一镜**的起点上，不是顺次挨着。
    @Test func narrationsFollowTheirOwnShots() throws {
        let p = plan(try job(shotCount: 3), measured: { [2.0, 4.0, 1.0][$0] })
        #expect(p.shotStarts == [0, 60, 180])
        #expect(p.narrations == [0: 0, 1: 60, 2: 180],
                "旁白落在 \(p.narrations) —— 第三镜那句会压在第二镜上")
    }

    /// 网关给了逐段时长就用它 —— 那是权威的，比本地实测准。
    @Test func theGatewayListWinsOverLocalMeasurement() throws {
        let clips = #","shot_clips":[{"file":"a.mp4","seconds":2},{"file":"b.mp4","seconds":6}]"#
        let p = plan(try job(shotCount: 2, shotClips: clips),
                     measured: { _ in Issue.record("有权威时长还去量文件"); return 99 })
        #expect(p.shotStarts == [0, 60])
    }

    /// 一镜读不出时长（文件坏了）—— 拿别的镜顶上，**不许把整片压扁**。
    @Test func oneUnreadableShotDoesNotFlattenTheFilm() throws {
        let p = plan(try job(shotCount: 4), measured: { [3.0, 0, 5.0, 9.0][$0] })
        #expect(p.shotStarts == [0, 90, 240, 390],
                "读不出的那一镜顶错了长度：\(p.shotStarts)")
    }

    /// **主音量差要跟着这份铺法一起算出来** —— 它是同一个决定的一部分。
    @Test func theMasterGainRidesAlongWithThePlan() throws {
        let plain = plan(try job(shotCount: 2), measured: { _ in 3 })
        #expect(plain.volume == 1, "网关没给主音量差时不该瞎补")

        let corrected = plan(try job(shotCount: 2, gain: #","master_gain_db":5.8"#),
                             measured: { _ in 3 })
        let draftLUFS = -16.0, timelineLUFS = -21.8
        #expect(abs(timelineLUFS + 20 * log10(corrected.volume) - draftLUFS) < 0.5,
                "补完是 \(timelineLUFS + 20 * log10(corrected.volume)) LUFS，草案是 \(draftLUFS)")
    }
}
