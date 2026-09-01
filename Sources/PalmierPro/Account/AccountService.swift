import AppKit
import Foundation

/// Account state comes only from the METAG gateway: `/api/v1/me` owns the balance and
/// paid status, `/api/v1/pricing` owns plans and the signup grant.
///
/// The upstream Convex account model (tier, monthly budget, spent-this-period, renewal
/// date) has no gateway equivalent and was removed rather than rendered from invented
/// numbers.
@Observable
@MainActor
final class AccountService {
    static let shared = AccountService()

    private static let allowedBillingHosts: Set<String> = [
        "checkout.stripe.com",
        "billing.stripe.com",
    ]

    private(set) var isLoading: Bool = true
    private(set) var isMisconfigured: Bool = false
    private(set) var lastError: String?
    private(set) var isSigningIn: Bool = false

    /// 登录这件事走到哪一步了。**空着的等待是最贵的等待** —— 用户从浏览器
    /// 回到 app，屏幕上什么都不动，他不知道是成了、卡了、还是白扫了
    /// （2026-08-31 创始人：「过了很久才有响应」）。
    ///
    /// 三步各有话说，最后一步是**他拿到了什么**，不是"操作成功"。
    enum SignInPhase: Equatable {
        case idle
        /// 浏览器开着，人在微信那一侧 —— 我们这里什么都不知道。
        case waiting
        /// 票回来了，正在跟网关核对。这一段是我们自己的，约一个来回。
        case finishing
        /// 落地。带上余额 —— 这是他这一趟真正换到的东西。
        case landed(credits: Int)
    }

    private(set) var signInPhase: SignInPhase = .idle
    @ObservationIgnored private var landingTask: Task<Void, Never>?
    private(set) var isBuyingCredits: Bool = false

    private(set) var metagCredits: Int = 0
    private(set) var isPaid: Bool = false
    private(set) var plans: [MetagGateway.Pricing.Plan] = []
    /// Signup grant from the gateway. Nil when unknown — callers must fall back to copy
    /// that states no number at all.
    private(set) var signupFreeCredits: Int?

    /// Verified email from the gateway, or nil. The only user-facing identity we have —
    /// `sub` is `provider:id` and must never reach the UI.
    private(set) var email: String?

    @ObservationIgnored private var didConfigure = false
    @ObservationIgnored private var buyCreditsTask: Task<Void, Never>?

    private init() {}

    var isSignedIn: Bool { MetagGateway.isSignedIn }
    var aiAllowed: Bool { isSignedIn }
    var remainingCredits: Int { metagCredits }
    var hasCredits: Bool { remainingCredits > 0 }

    var creditPack: MetagGateway.Pricing.Plan? { plans.first { !$0.isSubscription } }
    var subscriptionPlans: [MetagGateway.Pricing.Plan] { plans.filter(\.isSubscription) }

    func configure() {
        guard !didConfigure else { return }
        didConfigure = true
        isMisconfigured = false
        Task {
            await refreshPricing()
            await refreshMetagAccount()
            isLoading = false
        }
    }

    func refreshPricing() async {
        do {
            let pricing = try await MetagGateway.pricing()
            plans = pricing.plans
            signupFreeCredits = pricing.signup_free_credits
        } catch {
            Log.account.warning("pricing fetch failed error=\(error.localizedDescription)")
        }
    }

    func refreshMetagAccount() async {
        guard MetagGateway.isSignedIn else {
            metagCredits = 0
            isPaid = false
            return
        }
        do {
            let account = try await MetagGateway.account()
            metagCredits = account.credits
            isPaid = account.subscribed
            email = account.email
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Sign in

    func signIn(with provider: MetagAuth.Provider) async {
        guard !isSigningIn else {
            lastError = "Sign-in is already in progress."
            return
        }
        isSigningIn = true
        lastError = nil
        landingTask?.cancel()
        signInPhase = .waiting
        defer { isSigningIn = false }
        do {
            // 账号是 `MetagAuth` 验票时**已经拿到的那一份**，不再多打一个来回。
            let account = try await MetagAuth.shared.signIn(with: provider) {
                self.signInPhase = .finishing
            }
            metagCredits = account.credits
            isPaid = account.subscribed
            email = account.email
            land(credits: account.credits)
        } catch {
            signInPhase = .idle
            lastError = error.localizedDescription
            Log.account.warning(
                "sign in failed provider=\(provider.rawValue)",
                telemetry: "Sign in failed",
                data: ["provider": provider.rawValue]
            )
        }
    }

    /// 落地那句话停几秒就走 —— 它是一次庆祝，不是一块常驻的横幅。
    ///
    /// **但那几秒从他看见开始数，不是从票到账开始数。** 授权是在另一扇窗里
    /// 完成的，他扫完码人还在那一侧；等他切回来，六秒早过完了
    /// （2026-08-31 创始人：「注意力始终在网页端，回到 Mac 端才看到最后那行字」——
    /// 他这次赶上了，下次慢十秒就赶不上）。
    ///
    /// 所以 app 不在前台就先不开始计时，等他回来再数。
    private func land(credits: Int) {
        signInPhase = .landed(credits: credits)
        landingTask = Task { [weak self] in
            await waitUntilAppIsFrontmost()
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.signInPhase = .idle
        }
    }

    func signOut() async {
        landingTask?.cancel()
        signInPhase = .idle
        MetagAuth.shared.signOut()
        metagCredits = 0
        isPaid = false
    }

    // MARK: - Billing

    /// `planId` must come from `/api/v1/pricing`; the gateway checkout accepts no others.
    func subscribe(planId: String) async {
        await openCheckout(plan: planId)
    }

    func buyCreditPack() {
        guard !isBuyingCredits, let pack = creditPack else { return }
        isBuyingCredits = true
        buyCreditsTask = Task { @MainActor [weak self] in
            defer {
                self?.isBuyingCredits = false
                self?.buyCreditsTask = nil
            }
            await self?.openCheckout(plan: pack.id)
        }
    }

    private func openCheckout(plan: String) async {
        lastError = nil
        do { openInBrowser(try await MetagGateway.checkoutURL(plan: plan)) }
        catch { lastError = error.localizedDescription }
    }

    private func openInBrowser(_ urlString: String) {
        guard let url = URL(string: urlString),
              url.scheme == "https",
              let host = url.host,
              Self.allowedBillingHosts.contains(host)
        else {
            lastError = "Refused to open untrusted URL."
            return
        }
        NSWorkspace.shared.open(url, configuration: .init(), completionHandler: nil)
    }
}

// MARK: - Display helpers

extension AccountService {
    /// Verified email when we have one. Never `sub` — that is an internal identifier.
    var displayPrimaryText: String {
        guard isSignedIn else { return "Signed out" }
        return email ?? "Signed in"
    }

    /// Second line: the plan, unless the first line already used it.
    var displaySecondaryText: String? {
        guard isSignedIn else { return nil }
        return planLabel
    }

    /// First letter of the verified email, else nil — we never invent one from `sub`.
    var displayInitial: String? {
        guard isSignedIn, let first = email?.trimmingCharacters(in: .whitespaces).first else { return nil }
        return String(first).uppercased()
    }

    var planLabel: String { isPaid ? "Subscribed" : "Free" }
}

/// 等到 app 回到前台；已经在前台就立刻返回。
///
/// 用在"这句话要等他看见"的地方 —— 计时从他的注意力回来那一刻开始，
/// 不是从事情办完那一刻开始。
///
/// **`NSApp` 会是 nil**（单测里就没有 NSApplication，隐式解包当场崩）。
/// 没有 app 就没有"前台"可等，直接返回。
@MainActor
func waitUntilAppIsFrontmost() async {
    guard let app: NSApplication = NSApp, !app.isActive else { return }
    var observer: (any NSObjectProtocol)?
    await withCheckedContinuation { continuation in
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in continuation.resume() }
    }
    if let observer { NotificationCenter.default.removeObserver(observer) }
}
