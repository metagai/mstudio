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

    /// 订阅到哪天为止，以及**为什么是这个状态**。
    ///
    /// 只有布尔的时候，「他自己取消了」和「他的卡扣不动了」在界面上长得一样 ——
    /// 而这两件事要他做的事完全相反：前者什么都不用做（别让他以为已经断了），
    /// 后者要他去换卡（且必须说清现在还没断）。
    enum SubscriptionState: Equatable {
        /// 从来没订过 —— 这一行整个不出现。
        case none
        /// 正常续费。只报日期，不催不劝。
        case active(until: Date)
        /// 已取消，但还能用到期末。
        case canceling(until: Date)
        /// 这个月没扣成功。Stripe 还会重试两三周，**这段时间他该照常用**。
        case pastDue
        /// 已经到期。
        case ended
    }

    private(set) var subscription: SubscriptionState = .none
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
            apply(try await MetagGateway.account())
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 一份账号落到界面状态上。**只有这一处** —— 登录那条路和刷新那条路
    /// 各解析一遍的话，两边迟早会不一样。
    private func apply(_ account: MetagGateway.Account) {
        metagCredits = account.credits
        isPaid = account.subscribed
        email = account.email
        subscription = Self.state(until: account.sub_until, status: account.sub_status)
    }

    /// 网关那两格 → 界面那一句。
    ///
    /// **状态由 `sub_status` 说了算，日期只是它的补充。** 反过来推
    /// （"有日期就是订着"）会把"卡扣不动了"讲成"一切正常"。
    static func state(until: Int?, status: String?) -> SubscriptionState {
        let date = (until ?? 0) > 0 ? Date(timeIntervalSince1970: TimeInterval(until ?? 0)) : nil
        switch status {
        case "canceling": return date.map(SubscriptionState.canceling) ?? .ended
        case "past_due": return .pastDue
        case "active": return date.map(SubscriptionState.active) ?? .none
        case "ended": return .ended
        default: return .none
        }
    }

    /// Stripe 自助门户。没付过费的人网关回 404 —— 那时不给链接，
    /// 而不是给一个点进去报错的链接。
    func openBillingPortal() async {
        do {
            guard let url = URL(string: try await MetagGateway.billingPortalURL()) else { return }
            NSWorkspace.shared.open(url)
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
            apply(account)
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
        subscription = .none
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
        do {
            let url = try await MetagGateway.checkoutURL(plan: plan)
            guard openInBrowser(url) else { return }
            // **只在真的交出去之后才记。** 记在"我发起了跳转"上，
            // 转化率会凭空变好而钱一分没进来 —— 和把 `paid` 记在按钮上是同一个坑。
            //
            // `handoff` 说清这一格在 Mac 上比 web 松一档：web 记的是
            // "那一页真的打开了"，我们只知道自己把它交给了系统浏览器。
            MetagFunnel.track(.checkoutOpen, meta: ["plan": plan, "handoff": true])
            watchForPayment()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 他付完钱、切回 Mac 的那一刻。
    ///
    /// ## 之前什么都不做
    ///
    /// `openCheckout` 把浏览器打开、埋一个漏斗点，然后就结束了 ——
    /// 没有 `didBecomeActive`、没有轮询、没有回跳处理。
    /// **他付了钱、Stripe 说成功、切回 Mac，credits 胶囊还是付款前那个数**
    /// （可能还是红色的 0）。
    ///
    /// 他不会再等等，他会发邮件问、或者要求退款 ——
    /// **这是整条转化链上最贵的一次断裂，就发生在他刚决定信任我们之后的三秒。**
    ///
    /// ## 为什么要重试好几轮
    ///
    /// 入账走 Stripe 的 webhook，有延迟。切回来立刻问一次多半还是旧数 ——
    /// **只问一次等于没问**。间隔按 webhook 的实际尺度排（见 `paymentPollDelays`）。
    ///
    /// ## 等不到也不假装
    ///
    /// 跑完还没到账就说一句实话，并指向他能自己看的地方（额度流水）——
    /// 而不是沉默，也不是说"失败了"（钱很可能已经收了）。
    private func watchForPayment() {
        Task { @MainActor in
            await waitUntilAppIsFrontmost()
            let before = metagCredits
            for delay in Self.paymentPollDelays {
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                await refreshMetagAccount()
                if metagCredits > before { return }
            }
            lastError = L10n.string("Payment may still be processing — your balance will update on its own. You can check credit activity any time.")
        }
    }

    /// 切回来之后问余额的节奏（秒）。
    ///
    /// **总跨度要盖得住 webhook 的延迟** —— 只等两三秒等于没等。
    static let paymentPollDelays: [Int] = [0, 3, 6, 12]

    /// 交出去了返回 true。**拒绝打开也是一种结果**，不能被当成成功。
    @discardableResult
    private func openInBrowser(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              url.scheme == "https",
              let host = url.host,
              Self.allowedBillingHosts.contains(host)
        else {
            lastError = "Refused to open untrusted URL."
            return false
        }
        NSWorkspace.shared.open(url, configuration: .init(), completionHandler: nil)
        return true
    }
}

// MARK: - Display helpers

extension AccountService {
    /// Verified email when we have one. Never `sub` — that is an internal identifier.
    /// 这张卡最上面那行字。
    ///
    /// **原来没登录时写的是 "Signed out"** —— 两处问题：它是个裸字面量
    /// （压根没登记过，非英文用户看到的就是这两个英文词），
    /// 而且它在**描述机器自己的状态**。在他能按下登录的那张卡上，
    /// 最大的字应该说清他能换到什么。
    ///
    /// 换成产品里本来就在用的那句承诺（网关的临时身份过期文案是同一句），
    /// **一件事全产品一个说法。**
    var displayPrimaryText: String {
        guard isSignedIn else { return L10n.string("Sign in and your films stay with you") }
        return email ?? L10n.string("Signed in")
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
func waitUntilAppIsFrontmost(timeout: Duration = .seconds(120)) async {
    guard let app: NSApplication = NSApp else { return }   // 没有 app 就没有"前台"可等

    // **等要有个头。**
    //
    // 第一版挂在 `didBecomeActiveNotification` 上，没有上限 —— 而那条通知
    // 可能永远不来：单测进程里 `NSApp` 存在但永远不会 active，于是 await
    // 挂死，整套测试从 15 秒变成 20 分钟不结束（2026-09-01 实测）。
    // 生产里是同一个形状：他把 app 丢在后台不管，那句庆祝就永远挂着。
    //
    // 用轮询而不是通知 + 超时竞速：那个写法要么双重 resume（崩），
    // 要么编译器查不动隔离。250 毫秒的粒度对"开始数 6 秒"完全够用，
    // 而这段代码简单到不会再出错。
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !app.isActive, ContinuousClock.now < deadline, !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(250))
    }
}

