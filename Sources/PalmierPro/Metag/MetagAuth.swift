import AppKit
import AuthenticationServices

/// METAG 三方登录：系统 Web 认证会话 → `metag://auth#token=<jwt>` → Keychain。
/// 网关已支持 client=mac 回跳（gateway/src/main.rs oauth_callback）。
@MainActor
final class MetagAuth: NSObject {
    static let shared = MetagAuth()

    enum Provider: String, CaseIterable {
        case google, apple, github

        var title: String {
            switch self {
            case .google: return "Google"
            case .apple: return "Apple"
            case .github: return "GitHub"
            }
        }
    }

    private var session: ASWebAuthenticationSession?

    func signIn(with provider: Provider) async throws {
        let url = MetagGateway.baseURL
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
