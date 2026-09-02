import Foundation
import Testing
@testable import PalmierPro

/// 「我的作品」那一屏。**它叫"我的作品"、列的是片子，而在这之前整屏是文字。**
///
/// 我原本要网关加一个 `first_frame`。产品技术负责人否掉了，理由比我的提议好：
/// **首帧只活在 Redis 的任务哈希里，过了 TTL 就没有** —— 缩略图会随着时间
/// 一张张消失，那比一张都没有更糟。他改成回 `poster: "shot_0.mp4"`：
/// 每一条成片都有，而且它就是第一镜本身。
@Suite("我的作品")
struct MyFilmsTests {
    private static func source(_ name: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PalmierPro/\(name)")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// 网关新给的两格要真的解出来 —— 少解一个，界面就当它不存在。
    @Test func theRowKeepsWhatTheGatewaySends() throws {
        let json = """
        {"job_id":"j1","status":"done","engine":"seedance","shots":4,"credits":120,
         "created_at":1788265812,"prompt":"a woman folds laundry","retrievable":true,
         "refunded":true,"poster":"shot_0.mp4"}
        """.data(using: .utf8)!
        let row = try JSONDecoder().decode(MetagGateway.FilmRow.self, from: json)
        #expect(row.poster == "shot_0.mp4")
        #expect(row.refunded == true)
    }

    /// **老网关不回这两格也不能整条解不出来。** 一个字段让整张列表消失，
    /// 比没有那个字段糟得多。
    @Test func anOlderGatewayStillDecodes() throws {
        let json = """
        {"job_id":"j1","status":"done","engine":"local","shots":2,"credits":8,
         "created_at":1788265812,"prompt":null,"retrievable":false}
        """.data(using: .utf8)!
        let row = try JSONDecoder().decode(MetagGateway.FilmRow.self, from: json)
        #expect(row.poster == nil)
        #expect(row.refunded == nil)
    }

    /// **失败又退过款的，不能只报一个扣费数字。**
    /// 「没渲成 · 120 credits」读起来就是"失败了还扣我钱"。
    @Test func arefundedFilmDoesNotLookLikeACharge() {
        let src = Self.source("Metag/MetagMyFilms.swift")
        #expect(src.contains("f.refunded == true"),
                "退过款的又显示成扣费了 —— 用户读到的是'失败了还扣我钱'")
        #expect(src.contains("shots · refunded"))
    }

    /// 缩略图取一次就够：列表滚动时 SwiftUI 会反复调 body。
    @Test func postersAreFetchedOnce() {
        let src = Self.source("Metag/MetagPosterCache.swift")
        #expect(src.contains("guard images[jobId] == nil, !inFlight.contains(jobId)"),
                "同一行重绘会重下一次 —— 一屏十行就是十次")
    }

    /// **取不到就不摆图** —— 一张占位的假图会让人以为片子长那样。
    @Test func nothingIsInventedWhenThereIsNoPoster() {
        #expect(Self.source("Metag/MetagPosterCache.swift").contains("else { return nil }"))
        #expect(Self.source("Metag/MetagMyFilms.swift").contains("guard let name = f.poster else { return }"))
    }
}
