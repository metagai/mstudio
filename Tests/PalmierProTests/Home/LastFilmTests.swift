import Foundation
import Testing
@testable import PalmierPro

/// **一个刚回来的创作者，零点击就能看见自己上次做的东西。**
///
/// 创始人 2026-08-10 点名：「最近的项目和 Template Lib 有待重新设计
/// （交互不 Aha 是原罪）」。2026-09-04 核实，Mac 在这条判据上是 0 分——
/// 首页三块（问话+样片、样例工程、本地文件列表）没有一样是他自己的，
/// 他真正的片子在编辑器的素材面板里。
@Suite("上一条片子")
struct LastFilmTests {

    private func row(
        id: String, retrievable: Bool = true, status: String = "done",
        poster: String? = "shot_0.mp4", at: Double = 1_000
    ) throws -> MetagGateway.FilmRow {
        let poster = poster.map { "\"\($0)\"" } ?? "null"
        return try JSONDecoder().decode(MetagGateway.FilmRow.self, from: Data("""
        {"job_id":"\(id)","status":"\(status)","engine":"local","shots":3,
         "credits":30,"created_at":\(at),"prompt":"天台上的灯",
         "retrievable":\(retrievable),"refunded":false,"poster":\(poster)}
        """.utf8))
    }

    /// 有片子就摆他的。
    @Test func picksHisNewestFilm() throws {
        let films = [try row(id: "a"), try row(id: "b")]
        #expect(LastFilm.pick(films)?.job_id == "a", "列表是新到旧，第一条就是上一次那部")
    }

    /// **只摆打得开的那条。**
    /// 一张点下去说"取不到了"的卡片，比空着更糟：
    /// 它把"接着上次那股劲"变成了一次失望。
    @Test func skipsTheOnesHeCannotOpen() throws {
        #expect(LastFilm.pick([try row(id: "gone", retrievable: false)]) == nil)
        #expect(LastFilm.pick([try row(id: "failed", status: "failed")]) == nil)
        #expect(LastFilm.pick([try row(id: "noposter", poster: nil)]) == nil,
                "没有 shot_0.mp4 就没有能动的东西 —— 摆一张静止的海报不是这一格的意思")
    }

    /// 坏的排在前面时，往后找到第一条好的。
    @Test func fallsThroughToTheFirstOpenableOne() throws {
        let films = [
            try row(id: "gone", retrievable: false),
            try row(id: "failed", status: "failed"),
            try row(id: "good"),
        ]
        #expect(LastFilm.pick(films)?.job_id == "good")
    }

    /// 一条都没有 —— 那是第一次来的人，首屏该留给别人的样片和那句问话。
    @Test func newcomersStillSeeTheShowcase() {
        #expect(LastFilm.pick([]) == nil)
    }

    /// **选对了不等于看得见。**
    ///
    /// 上面四条测的是"摆哪一条"，而创始人那句话是"**零点击就能看见**"。
    /// 所以再问一次屏幕：那一格真的画出东西了吗，还是一块空白。
    /// 量的是像素，不是源码里那个 `if` 还在不在。
    @MainActor
    @Test func itActuallyLandsOnTheScreen() throws {
        let film = try row(id: "a")
        let bitmap = try ViewInk.bitmap(of: LastFilm(film: film, onOpen: {}), width: 360)
        let lit = ViewInk.litPixels(bitmap)
        #expect(lit > 400,
                "首屏那一格只画出 \(lit) 个像素 —— 他回来第一眼看不见自己上次做的东西")
    }
}
