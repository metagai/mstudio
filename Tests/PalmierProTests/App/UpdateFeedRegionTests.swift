import Foundation
import Testing
@testable import PalmierPro

/// **国内用户去国内那份 appcast 取更新。**（A0j）
///
/// `Info.plist` 里的 `SUFeedURL` 写死 `metag.ai`，而合伙人 08-16 实测国内取
/// metag.ai 的大文件是 **14 KB/s** —— 76MB 是 37 分钟量级，**没有人会等完**。
/// 也就是说在这之前，国内已装用户的自动更新等于不存在，
/// 而它一直是绿的：那个 xml 才几 KB，跨洋取得到，Sparkle 一声不响。
@Suite("更新去哪儿取")
struct UpdateFeedRegionTests {

    @Test(arguments: [("zh", "metag-ai.com"), ("en", "metag.ai"), ("es", "metag.ai")])
    func theFeedFollowsTheInterfaceLanguage(language: String, host: String) {
        let url = Updater.feedURL(language: language)
        #expect(url.host() == host, "\(language) 去了 \(url.host() ?? "?") 取更新")
        #expect(url.path() == "/mac/appcast.xml")
    }

    /// **跟界面语言走，不跟服务端 region 走。**
    ///
    /// 后者在国内网关重启时会被 nginx 静默兜到海外（合伙人 2026-09-01 实测），
    /// 而客户端不该继承那个抖动 —— `downloadPage` 早就是这条规矩，这里跟上。
    /// 判据钉的是"它和下载页去同一个域"，那是行为，不是源码字符串。
    ///
    /// ⚠ **这一条单独存在是不够的**：把 `siteRoot` 两个分支都改成国内域，
    /// 它照样绿（两边一起错，"一致"仍然成立），而上面那条当场红。
    /// 变异实测过 —— **两条测的不是同一件事，缺哪条都有一种坏法漏掉。**
    @Test(arguments: ["zh", "en"])
    func theFeedAndTheDownloadPageAgree(language: String) {
        #expect(Updater.feedURL(language: language).host()
                == MetagShowcase.siteRoot(language: language).host())
    }
}
