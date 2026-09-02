import Foundation
import Testing
@testable import PalmierPro

/// **他看的那条片子，和他拿到的那条不是同一条。**
///
/// 网关把配乐从草案那次混音里单独分出来（`music_bed`：除旁白之外的全部，
/// 已经压过电平、被旁白闪避过），注释写明了用途 ——
/// 「编辑器把它铺在那 N 段下面，听到的就是他刚才看的那一条」。
///
/// **而 Mac 一直没下过它。** 用户看的是一条有配乐的草案，按下出片、
/// 付了钱，拿到的时间线上只有画面和旁白。
@Suite("时间线上的配乐")
struct ScoreOnTimelineTests {
    private static func source(_ name: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PalmierPro/\(name)")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    @Test func theJobKeepsTheMusicBed() throws {
        let json = """
        {"job_id":"j1","status":"done","error":null,"shots":[],"cover":null,
         "shots_done":0,"stage":null,"first_frames":null,"preview":"preview.mp4",
         "error_kind":null,"music_bed":"mix.m4a"}
        """.data(using: .utf8)!
        #expect(try JSONDecoder().decode(MetagGateway.Job.self, from: json).music_bed == "mix.m4a")
    }

    @Test func anOlderGatewayStillDecodes() throws {
        let json = """
        {"job_id":"j1","status":"done","error":null,"shots":[],"cover":null,
         "shots_done":0,"stage":null,"first_frames":null}
        """.data(using: .utf8)!
        #expect(try JSONDecoder().decode(MetagGateway.Job.self, from: json).music_bed == nil)
    }

    /// 片子落到时间轴上时要把配乐一起铺下去。
    @Test func theScoreIsLaidWithTheShots() {
        let src = Self.source("Metag/MetagJobOpener.swift")
        #expect(src.contains("job.music_bed"),
                "又只铺画面和旁白了 —— 他看的那条有配乐")
        #expect(src.contains("editor.addMediaAsset(from: url, type: .audio)"))
    }

    /// **一镜都没取到就别取配乐** —— 没有画面的一条音乐轨是垃圾。
    @Test func noShotsMeansNoScore() {
        #expect(Self.source("Metag/MetagJobOpener.swift").contains("if added > 0, let bed = job.music_bed"))
    }

    /// **取不到要说出来。** 少了配乐他会以为是我们没做，而不是没取到。
    @Test func aMissingScoreIsSaidOutLoud() {
        let src = Self.source("Metag/MetagJobOpener.swift")
        #expect(src.contains("no score."), "配乐没取到的时候一声不吭")
        #expect(src.contains("if !score {"))
    }
}
