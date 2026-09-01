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
        defer { isSigningIn = false }
        do {
            try await MetagAuth.shared.signIn(with: provider)
            await refreshMetagAccount()
        } catch {
            lastError = error.localizedDescription
            Log.account.warning(
                "sign in failed provider=\(provider.rawValue)",
                telemetry: "Sign in failed",
                data: ["provider": provider.rawValue]
            )
        }
    }

    func signOut() async {
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
