import Foundation
import Testing
@testable import PalmierPro

/// **"先看一眼"里的"看"。**
///
/// 草案那条能看的片子（`preview.mp4`，已经混过配乐）一直都在：
/// `cpu_worker` 出草案时就生成它，网关按字节区间下发，web 的幕布一直在播。
/// **只有 Mac 从来没解过 `preview` 这个字段** —— 于是这一屏给的是
/// 一排静态首帧加一堆输入框：那不是"看一眼"，那是"看一眼它的证据"。
@Suite("草案能看了")
struct DraftPlayerTests {
    private static func source(_ name: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PalmierPro/\(name)")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// 网关发的那个字段要真的解出来 —— 少解一个，界面就当它不存在。
    @Test func theJobKeepsThePreview() throws {
        let json = """
        {"job_id":"j1","status":"done","error":null,"shots":[],
         "cover":null,"shots_done":0,"stage":"music",
         "first_frames":["f0.png"],"preview":"preview.mp4"}
        """.data(using: .utf8)!
        let job = try JSONDecoder().decode(MetagGateway.Job.self, from: json)
        #expect(job.preview == "preview.mp4")
    }

    /// 老网关不回它也不能整条解不出来。
    @Test func anOlderGatewayStillDecodes() throws {
        let json = """
        {"job_id":"j1","status":"done","error":null,"shots":[],
         "cover":null,"shots_done":0,"stage":null,"first_frames":null}
        """.data(using: .utf8)!
        #expect(try JSONDecoder().decode(MetagGateway.Job.self, from: json).preview == nil)
    }

    /// 草案好了就播它，拿不到才退回场记板 —— **不留空白**。
    @Test func theCurtainOpensOntoTheFilm() {
        let src = Self.source("Metag/MetagDraftSheet.swift")
        #expect(src.contains("if let preview = model.job?.preview {"),
                "草案又只剩静态图了 —— 那不是'看一眼'")
        #expect(src.contains("MetagDraftPlayer("))
        #expect(src.contains("} else {\n                filmStrip\n            }"),
                "拿不到片子时留了空白")
    }

    /// **表关了声音要跟着停。** 一条在背景里继续说话的旁白，
    /// 比没有声音吓人得多。
    @Test func closingTheSheetStopsTheSound() {
        let src = Self.source("Metag/MetagDraftPlayer.swift")
        #expect(src.contains(".onDisappear"))
        #expect(src.contains("player?.pause()"))
    }
}
