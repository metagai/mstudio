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
    @Test @MainActor func appleComesFirstInEnglish() {
        #expect(MetagAuth.Provider.ordered(language: "en").first == .apple)
    }

    /// **中文界面里微信排第一。**
    ///
    /// 另外三家对国内用户基本上都是打不开的门 —— Google / GitHub 要翻墙，
    /// Apple ID 很多人没绑。让他在四个里找那个唯一能用的，
    /// 是我们本来可以替他省下的一步。
    @Test @MainActor func wechatComesFirstInChinese() {
        #expect(MetagAuth.Provider.ordered(language: "zh").first == .wechat)
    }

    /// 换顺序不许换掉谁 —— 四家一个都不能少。
    @Test(arguments: ["en", "zh", "es"]) @MainActor
    func reorderingNeverDropsAProvider(language: String) {
        #expect(Set(MetagAuth.Provider.ordered(language: language)) == Set(MetagAuth.Provider.allCases))
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

    /// **授权回调不许继承主线程隔离。**
    ///
    /// `MetagAuth` 是 `@MainActor`，所以写在它里面的闭包默认是主线程隔离的；
    /// 而 AuthenticationServices 在一条 XPC 回复队列上调它 —— Swift 6 运行时
    /// 当场核对隔离，对不上就 `__builtin_trap()`。2026-08-31 创始人五次
    /// 「扫完码就崩」，栈顶是：
    ///
    ///     _dispatch_assert_queue_fail
    ///     swift_task_checkIsolatedSwift
    ///     closure #1 in closure #2 in MetagAuth.signIn(with:)
    ///     -[ASWebAuthenticationSession _endSessionWithCallbackURL:error:]
    ///     _xpc_connection_reply_callout
    ///
    /// **这一条只能看源码。** 崩的是回调那一刻，而回调只有真机扫码才发生 ——
    /// 单测碰不到 `ASWebAuthenticationSession`，一次都没红过。
    /// 判据弱，但比没有强：`@Sendable` 一没，它就红。
    @Test func theAuthCallbackDoesNotInheritMainActorIsolation() throws {
        let src = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/PalmierPro/Metag/MetagAuth.swift"),
            encoding: .utf8
        )
        #expect(src.contains("callbackURLScheme: \"metag\") { @Sendable url, error in"),
                "授权回调又继承主线程隔离了 —— 扫完码那一刻整个 app 会消失")
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

/// **凡是把用户送出 app 的链接，都要送到他打得开的那个域。**
///
/// 微信授权、检查更新 —— 这两处都会把国内用户丢到一个多半打不开的站上，
/// 而那正是他主动来找我们的时刻。
@Suite("送出去的那些链接")
@MainActor
struct OutboundLinkTests {
    /// 检查更新原来写死 `metag.ai`。两个域都在发同一份落地页，
    /// 所以这不是二选一，是选近的那一个。
    @Test func theDownloadPageFollowsTheInterfaceLanguage() {
        // 界面语言此刻是什么由环境决定，这里只守"它必须是两者之一，且跟着语言走"。
        let expected = AppLocalization.shared.gatewayLanguage == "zh" ? "metag-ai.com" : "metag.ai"
        #expect(Updater.downloadPage.host() == expected)
    }

    /// 送出去的链接不许写死一个域 —— 写死的那个必然对一半用户是错的。
    @Test func noOutboundLinkHardcodesASingleDomain() throws {
        let src = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/PalmierPro/App/Updater.swift"),
            encoding: .utf8
        )
        #expect(src.contains("gatewayLanguage"), "检查更新又写死一个域了")
    }
}
