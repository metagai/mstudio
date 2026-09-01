import Foundation
import Testing
@testable import PalmierPro

@Suite("登录方式")
struct MetagAuthProviderTests {
    /// 四种都要给。网关那侧四条全是活的，之前只给 Google 是我们自己少给的。
    @Test func allFourProvidersAreOffered() {
        #expect(MetagAuth.Provider.allCases.map(\.rawValue) == ["apple", "google", "wechat", "github"])
    }

    /// **Apple 排第一。** 在 Mac 上它是"这个 app 属于这台电脑"的信号。
    @Test func appleComesFirst() {
        #expect(MetagAuth.Provider.allCases.first == .apple)
    }

    /// **微信只在 `metag-ai.com` 上存在。**
    ///
    /// 微信开放平台按 redirect_uri 白名单校验，而两个区各自用自己的 `PUBLIC_URL`
    /// 生成回调地址 —— 走 `api.metag.ai` 会被微信当场拒掉（实测 879 字节的
    /// 「redirect_uri 参数错误」）。而那个错**报在微信自己的页面上，
    /// 我们这边一条日志都没有** —— 所以这条必须由测试盯着，出问题时没有别的信号。
    @Test func wechatGoesToTheDomainItIsRegisteredOn() {
        #expect(MetagAuth.Provider.wechat.authBase.host() == "metag-ai.com")
    }

    /// **只有微信走别的域。** 一个登录方式不该决定整个客户端打哪个域 ——
    /// 出片、取件、报价在 api.metag.ai 上都是好的，把它们一起拖进区域分叉
    /// 是我们之前搁置区域解析的原因。
    @Test(arguments: [MetagAuth.Provider.apple, .google, .github])
    func everyoneElseUsesTheDefaultGateway(provider: MetagAuth.Provider) {
        #expect(provider.authBase == MetagGateway.baseURL)
    }

    @Test func everyProviderHasANameAndAnIcon() {
        for p in MetagAuth.Provider.allCases {
            #expect(!p.title.isEmpty)
            #expect(!p.systemImage.isEmpty)
        }
        // 品牌名不进翻译串 —— 各语言里都一样。
        #expect(MetagAuth.Provider.wechat.title == "WeChat")
    }
}
