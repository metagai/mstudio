import Foundation
import Testing
@testable import PalmierPro

/// **他打开第二天的片子时，那一句话说的是什么。**
///
/// 2026-09-02 产品技术负责人查出：网关超过 24 小时走 PG 归档路，
/// 那条路上一个用户文本都不回（隐私承诺，`subtitles: null` + `text_expired: true`）。
/// 于是第二天打开自己的作品：**N 段都在、配乐在、音量对，但每段没有字幕**。
///
/// Mac 这侧当时是**静默的** —— 什么都不说。他读到的是"字幕丢了"，
/// 而那像是我们弄丢了东西。**兑现了的承诺必须说出来，否则它读起来像故障。**
@Suite("打开一部作品之后那一句")
@MainActor
struct OpenedFilmMessageTests {
    private func line(captioned: Bool = false, textExpired: Bool = false,
                      score: Bool = true, narrations: Int = 3) -> String {
        MetagJobOpener.message(added: 5, narrations: narrations, captioned: captioned,
                               score: score, salvaged: false, textExpired: textExpired)
    }

    /// 过期那一句和普通那一句**必须不一样** —— 一样就等于没说。
    @Test func anExpiredCaptionIsNotSilent() {
        #expect(line(textExpired: true) != line(textExpired: false),
                "字幕按隐私承诺清掉了，屏幕上却和平时说一样的话 —— 他会以为丢了")
    }

    /// 而且要说清是**为什么**没有，不能只报数。
    @Test func itSaysWhyTheCaptionsAreGone() {
        let text = line(textExpired: true)
        #expect(text.contains("24"), "没提那 24 小时：\(text)")
        #expect(text.count > line(textExpired: false).count,
                "过期那一句比平时还短 —— 那不可能解释得清")
    }

    /// **字幕真铺上了的时候，不许再说"过期"。**
    /// 24 小时内重开一部片子会同时满足两边，先后顺序错了就自相矛盾。
    @Test func realCaptionsWinOverTheExpiryLine() {
        #expect(!line(captioned: true, textExpired: true).contains("24"),
                "字幕明明铺上了，还告诉他字幕过期了")
    }

    /// 一段都没取到的时候，说的仍然是"要重做"，不是字幕那句。
    @Test func nothingLoadedStillSaysRegenerate() {
        let text = MetagJobOpener.message(added: 0, narrations: 0, captioned: false,
                                          score: false, salvaged: false, textExpired: true)
        #expect(!text.contains("24"), "一段都没有还在解释字幕：\(text)")
    }
}
