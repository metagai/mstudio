import Foundation
import Testing
@testable import PalmierPro

/// **首屏那几条真片子。**
///
/// 线上 `metag.ai/media/showcase.json` 里 12 条完整样片，落地页一直在用，
/// 而 Mac 端一条都没接 —— 一个视频产品，第一屏一帧画面都没有。
@Suite("首屏的样片")
struct ShowcaseTests {
    /// 一份**和线上同形**的清单（字段名、嵌套、竖横都照抄真实那份）。
    private static let json = Data("""
    [
      {"id":"second-take","poster":"/media/sc-second-poster.jpg","reel":"/media/sc-second.mp4",
       "lines":{"zh":"第一遍不对，就再来一遍。","en":"If the first take isn't right, take it again.","es":"Si la primera toma no sale."},
       "recipe":{"resolution":"1280×720"}},
      {"id":"cat","poster":"/media/sc-cat-poster.jpg","reel":"/media/sc-cat.mp4",
       "lines":{"zh":"一句话，20 秒一镜到底。","en":"One sentence. Twenty seconds, one take."},
       "recipe":{"resolution":"1280×720"}},
      {"id":"pizza","poster":"/media/sc-pizza-poster.jpg","reel":"/media/sc-pizza.mp4",
       "lines":{"zh":"最后 3 秒，甲方出现了。","en":"In the last three seconds, the client shows up."},
       "recipe":{"resolution":"720×1280"}},
      {"id":"laundromat","poster":"/media/sc-laundromat-poster.jpg","reel":"/media/sc-laundromat.mp4",
       "lines":{"zh":"第四条不该出现在首屏。","en":"The fourth one should not reach the first screen."},
       "recipe":{"resolution":"720P"}}
    ]
    """.utf8)

    private static let root = URL(string: "https://metag.ai")!

    @Test func itReadsTheRealShape() {
        let films = MetagShowcase.firstScreen(Self.json, language: "zh", root: Self.root)
        #expect(films.count == 3, "首屏放了 \(films.count) 条 —— 这一屏的主角是那个输入框")
        #expect(films[0].line == "第一遍不对，就再来一遍。")
        #expect(films[0].poster.absoluteString == "https://metag.ai/media/sc-second-poster.jpg",
                "海报地址没拼对 —— 那一格会是空的")
        #expect(films[0].reel.absoluteString == "https://metag.ai/media/sc-second.mp4")
    }

    /// **竖片不能被裁成横的。** 12 条里真的有 720×1280 的。
    @Test func aPortraitFilmStaysPortrait() {
        let films = MetagShowcase.firstScreen(Self.json, language: "zh", root: Self.root)
        #expect(films[0].aspect > 1, "横片被当成竖的了")
        #expect(films[2].aspect < 1, "竖片被摆成横的 —— 海报会裁掉半张脸")
    }

    /// 没有那个语言就退回英文。**退回英文好过留空。**
    @Test func aMissingLanguageFallsBackToEnglish() {
        let films = MetagShowcase.firstScreen(Self.json, language: "es", root: Self.root)
        #expect(films[1].line == "One sentence. Twenty seconds, one take.",
                "西语没这一条，也没退回英文 —— 那一格是空的")
    }

    /// **缺哪一样就整条不要**，不摆一个点了播不出来的格子。
    @Test func anIncompleteEntryIsDropped() {
        let broken = Data("""
        [{"id":"no-reel","poster":"/media/a.jpg","lines":{"en":"x"}},
         {"id":"ok","poster":"/media/b.jpg","reel":"/media/b.mp4","lines":{"en":"y"}}]
        """.utf8)
        let films = MetagShowcase.firstScreen(broken, language: "en", root: Self.root)
        #expect(films.map(\.id) == ["ok"], "摆了一个点了播不出来的格子")
    }

    /// 清单取不到、或者回来的是一团别的东西 —— 首屏退回那三行例句，不能空。
    @Test func garbageNeverReachesTheScreen() {
        for junk in [Data(), Data("<html>502</html>".utf8), Data("{}".utf8)] {
            #expect(MetagShowcase.firstScreen(junk, language: "zh", root: Self.root).isEmpty)
        }
    }

    /// 中文界面走备案域 —— 国内打 `metag.ai` 那一排海报多半是空的。
    @Test func chineseGoesToTheDomainThatWorksInChina() {
        #expect(MetagShowcase.siteRoot(language: "zh").host == "metag-ai.com",
                "中文界面去了海外域 —— 那一排海报在国内多半是空的")
        #expect(MetagShowcase.siteRoot(language: "en").host == "metag.ai")
        #expect(MetagShowcase.siteRoot(language: "es").host == "metag.ai")
    }
}
