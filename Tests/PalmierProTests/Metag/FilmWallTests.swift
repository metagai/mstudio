import AppKit
import SwiftUI
import Testing
@testable import PalmierPro

/// **一面墙，不是一份日志。**
///
/// 「我的作品」列的是片子，而它原来长得像日志：一行提示词、一行
/// 「几镜 · 多少 credits · 多久以前」、右边一个状态词，前面一个 96pt 的小图。
/// 而每一条成片都带 `shot_0.mp4` —— 我们手里有画面，他看不到
/// （`docs/lessons.md` 第三十九条）。
@Suite("我的作品那面墙")
@MainActor
struct FilmWallTests {
    private static func film(
        status: String = "done", retrievable: Bool = true,
        refunded: Bool? = nil, shots: Int = 5, credits: Int = 120, poster: String? = "shot_0.mp4"
    ) -> MetagGateway.FilmRow {
        let json = """
        {"job_id":"j1","status":"\(status)","engine":"local","shots":\(shots),
         "credits":\(credits),"created_at":\(Date().timeIntervalSince1970 - 600),
         "prompt":"一个女孩在天台上看城市的灯","retrievable":\(retrievable),
         \(refunded.map { "\"refunded\":\($0)," } ?? "")
         \(poster.map { "\"poster\":\"\($0)\"," } ?? "")
         "_pad":0}
        """
        return try! JSONDecoder().decode(MetagGateway.FilmRow.self, from: Data(json.utf8))
    }

    /// 角标只在**他需要知道**的时候出现。
    /// 每张都贴一个「正常」，等于什么都没说。
    @Test func onlyTheOnesHeCannotOpenGetABadge() {
        #expect(!MetagFilmCard.showsBadge(status: "done", retrievable: true),
                "能打开的也挂角标 —— 一面墙上全是标签，他反而看不出哪一部出事了")
        #expect(MetagFilmCard.showsBadge(status: "done", retrievable: false))
        #expect(MetagFilmCard.showsBadge(status: "failed", retrievable: true))
    }

    /// 三种状态互不相同，而且都不是空的。
    @Test func eachStateSaysSomethingOfItsOwn() {
        let all = [
            MetagFilmCard.statusText(status: "done", retrievable: true),
            MetagFilmCard.statusText(status: "done", retrievable: false),
            MetagFilmCard.statusText(status: "failed", retrievable: true),
        ]
        #expect(all.allSatisfy { !$0.isEmpty })
        #expect(Set(all).count == 3, "几种状态共用了同一句话")
    }

    /// **失败又退过款的，不能只报一个扣费数字。**
    @Test func aRefundedFilmDoesNotReadAsACharge() {
        let refunded = MetagFilmCard.meta(Self.film(status: "failed", refunded: true, credits: 640))
        #expect(!refunded.contains("640"),
                "退过款的还印着 640 —— 他读到的是'失败了还扣我钱'：\(refunded)")
        #expect(MetagFilmCard.meta(Self.film(credits: 640)).contains("640"),
                "没退款的反而不说花了多少")
    }

    /// **海报还没到的时候，那张卡也得看得见。**
    ///
    /// 量的是屏幕上有没有东西，不是源码里那个分支还在不在 ——
    /// 一面墙如果在图到齐之前是空白，他看到的就是"这一屏坏了"。
    @Test func aCardIsVisibleBeforeItsPosterArrives() throws {
        let view = MetagFilmCard(
            film: Self.film(), poster: nil,
            onOpen: {}, onShare: {}, onDelete: {}
        ).frame(width: 240).padding()
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 272, height: 240)
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        var lit = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent > 0.05 {
                    lit += 1
                }
            }
        }
        #expect(lit > 800, "海报没到时那张卡只画出 \(lit) 个像素 —— 一面空白的墙")
    }
}
