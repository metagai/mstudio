import AppKit
import Foundation
import Testing
@testable import PalmierPro

/// 那块幕布。**仪式必须是真的，否则就是最坏的一种装饰。**
///
/// 这一组守两件事：格子数来自**网关报的真实镜数**（不是我们凑的），
/// 以及**它在落定那一刻不消失**——他刚看着它一格格填满，
/// 草案一好就被一堆输入框换掉的话，幕布是在最该拉开的那一刻合上了。
@Suite("幕布")
@MainActor
struct MetagFilmStripTests {
    private static func source(_ name: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PalmierPro/\(name)")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// **等待时和落定后是同一块。** 两处各写一遍的话，
    /// 迟早有一处被改掉，而切换的那一帧会闪。
    @Test func theCurtainStaysUpWhenTheDraftLands() throws {
        let src = Self.source("Metag/MetagDraftSheet.swift")
        let draftStage = try #require(src.range(of: "private var draftStage: some View {"))
        let tail = String(src[draftStage.lowerBound...].prefix(700))
        #expect(tail.contains("filmStrip"),
                "草案一好，他刚看着填满的那块画面就没了 —— 幕布在最该拉开的那一刻合上了")
        // 一处定义，两处引用。
        #expect(src.components(separatedBy: "MetagFilmStrip(").count == 2,
                "幕布被写了两遍 —— 两处迟早会不一样")
    }

    /// **没有任何动画由定时器驱动。** 和班底守同一条规矩：
    /// 一个按秒数假装进度的幕布，在片子卡住时还会欢快地拉开。
    @Test func nothingIsDrivenByATimer() {
        let src = Self.source("Metag/MetagFilmStrip.swift")
        for faked in ["Timer", "repeatForever", "autoreverses", "TimelineView", "Task.sleep"] {
            #expect(!src.contains(faked), "幕布里混进了 \(faked) —— 那就是按秒数演进度")
        }
    }

    /// 格子数用**网关报的镜数**；报不上来时按已到的张数摆，**不虚构格子**。
    @Test(arguments: [(4, 0, 4), (4, 2, 4), (0, 3, 3), (0, 0, 0), (2, 5, 5)])
    func slotsNeverInventShots(shots: Int, arrived: Int, expected: Int) {
        let frames = Dictionary(uniqueKeysWithValues: (0..<arrived).map {
            ($0, NSImage(size: NSSize(width: 1, height: 1)))
        })
        let strip = MetagFilmStrip(shots: shots, frames: frames)
        #expect(strip.slotCountForTesting == expected)
    }

    /// 全到齐才算落定 —— 差一格都不算。
    @Test(arguments: [(4, 3, false), (4, 4, true), (4, 5, true), (0, 0, false)])
    func settlingOnlyHappensWhenEveryFrameIsIn(shots: Int, arrived: Int, settled: Bool) {
        let frames = Dictionary(uniqueKeysWithValues: (0..<arrived).map {
            ($0, NSImage(size: NSSize(width: 1, height: 1)))
        })
        #expect(MetagFilmStrip(shots: shots, frames: frames).completeForTesting == settled)
    }
}
