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

    func signIn(with provider: Provider) async throws {
        let url = provider.authBase
            .appendingPathComponent("api/v1/auth/\(provider.rawValue)")
            .appending(queryItems: [URLQueryItem(name: "client", value: "mac")])

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "metag") { url, error in
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
        MetagGateway.token = Self.token(in: callback)
        // 匿名那一段和账号在这里接起来：漏斗的 anon 一直没变，
        // 从这一刻起网关能把两段认成同一个人。
        MetagFunnel.track(.signedIn, once: true)  // 一次会话登录一次
        guard MetagGateway.isSignedIn else { throw MetagGateway.Failure.signedOut }
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
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor() }
    }
}
