import AppKit
import AuthenticationServices

/// METAG 三方登录：系统 Web 认证会话 → `metag://auth#token=<jwt>` → Keychain。
/// 网关已支持 client=mac 回跳（gateway/src/main.rs oauth_callback）。
@MainActor
final class MetagAuth: NSObject {
    static let shared = MetagAuth()

    enum Provider: String, CaseIterable {
        case apple, google, wechat, github

        /// 名字不进翻译串 —— 这些是品牌名，各语言里都一样。
        var title: String {
            switch self {
            case .apple: return "Apple"
            case .google: return "Google"
            case .wechat: return "WeChat"
            case .github: return "GitHub"
            }
        }

        var systemImage: String {
            switch self {
            case .apple: return "apple.logo"
            case .google: return "globe"
            case .wechat: return "message.fill"
            case .github: return "chevron.left.forwardslash.chevron.right"
            }
        }

        /// 这一家的授权入口打哪个域。
        ///
        /// **微信只在 `metag-ai.com` 上存在。** 微信开放平台按 redirect_uri 白名单
        /// 校验，而两个区各自用自己的 `PUBLIC_URL` 生成回调地址 —— 走
        /// `api.metag.ai` 会被微信当场拒掉（实测：879 字节的
        /// 「redirect_uri 参数错误」）。
        ///
        /// **而那个错报在微信自己的页面上，我们这边一条日志都没有** ——
        /// 先做界面再联调的话，会盯着 Mac 的代码查很久。
        ///
        /// 只有这一条走别的域：**一个登录方式不该决定整个客户端打哪个域**，
        /// 出片、取件、报价在 api.metag.ai 上都是好的。
        var authBase: URL {
            self == .wechat
                ? URL(string: "https://metag-ai.com")!
                : MetagGateway.baseURL
        }
    }

    private var session: ASWebAuthenticationSession?

    /// 授权面板挂在哪扇窗上。**在主线程上先取好，存在这里。**
    ///
    /// AuthenticationServices 会在**任意线程**上回来问锚点 —— 这就是
    /// `presentationAnchor(for:)` 被声明成 `nonisolated` 的原因。
    /// 那里原来写的是 `MainActor.assumeIsolated { NSApp.keyWindow … }`，
    /// 而 `assumeIsolated` 猜错时不是抛错，是 `__builtin_trap()`：
    /// 进程当场消失，stderr 上一行 Swift 报错都没有（系统日志里只留下一句
    /// `BUG IN CLIENT OF LIBDISPATCH: Block was expected to execute on
    /// queue [com.apple.main-thread]`）。
    ///
    /// 在用户那一侧，它长得**和"登录成功之后被静默退出"一模一样** ——
    /// 2026-08-31 创始人扫完码后撞的四次崩溃，就是这个。
    private nonisolated(unsafe) var anchor: ASPresentationAnchor?

    func signIn(with provider: Provider) async throws {
        let url = provider.authBase
            .appendingPathComponent("api/v1/auth/\(provider.rawValue)")
            .appending(queryItems: [URLQueryItem(name: "client", value: "mac")])

        // 锚点在这里取（主线程），不在回调里取。
        anchor = NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? NSApp.windows.first

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            // **`@Sendable` 不是装饰。**
            //
            // `MetagAuth` 是 `@MainActor`，所以这个闭包在这里写下来时**默认继承主线程隔离**。
            // 而 AuthenticationServices 是在一条 XPC 回复队列上调它的（扫完码那一刻），
            // Swift 6 的运行时于是当场核对隔离 —— `swift_task_checkIsolatedSwift`
            // → `dispatch_assert_queue` → `__builtin_trap()`：
            //
            //     closure #1 in closure #2 in MetagAuth.signIn(with:)
            //     -[ASWebAuthenticationSession _endSessionWithCallbackURL:error:]
            //     _xpc_connection_reply_callout
            //
            // 进程当场消失，一行 Swift 报错都没有。用户看到的是"扫完码就被退出了"。
            // 2026-08-31 创始人连撞五次的就是这一行。
            //
            // 单测一次都没红过 —— 崩的是回调那一刻，而回调只有真机扫码时才发生。
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "metag") { @Sendable url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? MetagGateway.Failure.signedOut)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            session.start()
        }
        guard let issued = Self.token(in: callback), MetagTicket.isSignedIn(issued) else {
            throw MetagGateway.Failure.signedOut
        }

        // **存之前先验它在我们真正要用的那个网关上认不认。**
        //
        // 微信只能在 metag-ai.com 上完成（国内备案域名），而其余请求都打
        // MetagGateway.baseURL。两个区如果不共用签名密钥，那张票在这边一律 401 ——
        // 而我们撞 401 就清票，于是用户"登录成功"之后大约 50 秒被静默退出。
        // 2026-09-01 创始人真机撞到的就是这个。
        //
        // 验一下就能把"静默退出"换成一句当场说得清的话。
        let previous = MetagGateway.token
        MetagGateway.token = issued
        do {
            _ = try await MetagGateway.account()
        } catch {
            MetagGateway.token = previous
            Log.account.warning("sign-in token rejected by \(MetagGateway.baseURL.host() ?? "gateway"): \(error.localizedDescription)")
            throw MetagGateway.Failure.tokenNotAcceptedHere(provider: provider.title)
        }

        // 匿名那一段和账号在这里接起来：漏斗的 anon 一直没变，
        // 从这一刻起网关能把两段认成同一个人。
        MetagFunnel.track(.signedIn, once: true)  // 一次会话登录一次
    }

    func signOut() {
        MetagGateway.token = nil
    }

    /// token 在 fragment 里（`metag://auth#token=...`），URLComponents 不解析 fragment 的键值对
    static func token(in url: URL) -> String? {
        guard let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment else { return nil }
        for pair in fragment.split(separator: "&") where pair.hasPrefix("token=") {
            return String(pair.dropFirst("token=".count)).removingPercentEncoding
        }
        return nil
    }
}

extension MetagAuth: ASWebAuthenticationPresentationContextProviding {
    /// **这里一个主线程假设都不许有** —— 见 `anchor` 上面那段。
    /// 只读一个开始授权前就写好的引用。
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor ?? ASPresentationAnchor()
    }
}
