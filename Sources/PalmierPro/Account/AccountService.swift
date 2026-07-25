import AppKit
import Foundation
import Combine
import ClerkKit
import ClerkConvex
@preconcurrency import ConvexMobile

enum AccountTier: String, Decodable, Sendable {
    case none, pro, max

    var isPaid: Bool { self != .none }

    var planLabel: String {
        switch self {
        case .none: return L10n.key("Free")
        case .pro: return L10n.key("Pro plan")
        case .max: return L10n.key("Max plan")
        }
    }

    var upgradeLabel: String {
        switch self {
        case .none: return ""
        case .pro: return "Pro"
        case .max: return "Max"
        }
    }
}

struct AccountUser: Decodable, Sendable {
    let email: String?
    let name: String?
    let image: String?
    let tier: AccountTier
    let currentPeriodEnd: Double?
    let cancelAtPeriodEnd: Bool?
    let spentCreditsThisPeriod: Int?
    let purchasedCredits: Int?

    var displayName: String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespaces),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    var firstName: String? {
        displayName?.split(separator: " ").first.map(String.init)
    }
}

struct AccountPlan: Decodable, Sendable {
    let tier: AccountTier
    let monthlyPriceUsd: Int
    let monthlyBudgetCredits: Int?
}

struct AvailablePlan: Decodable, Sendable, Identifiable {
    let tier: AccountTier
    let monthlyPriceUsd: Int
    let discountedMonthlyPriceUsd: Int?
    let monthlyBudgetCredits: Int?

    var id: String { tier.rawValue }
    var effectiveMonthlyPriceUsd: Int {
        hasDiscount ? discountedMonthlyPriceUsd! : monthlyPriceUsd
    }
    var hasDiscount: Bool {
        guard let discounted = discountedMonthlyPriceUsd else { return false }
        return discounted < monthlyPriceUsd
    }
}

struct AccountResponse: Decodable, Sendable {
    let user: AccountUser
    let plan: AccountPlan?
}

enum TopOffLimits {
    static let minDollars = 5
    static let maxDollars = 1000
}

private struct UrlResponse: Decodable, Sendable {
    let url: String
}

private struct OkResponse: Decodable, Sendable {
    let ok: Bool
}

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
    private(set) var account: AccountResponse?
    private(set) var availablePlans: [AvailablePlan] = []
    private(set) var lastError: String?
    private(set) var isSigningIn: Bool = false
    private(set) var isBuyingCredits: Bool = false
    private(set) var authState: AuthState<String> = .loading

    private(set) var metagCredits: Int = 0

    var isSignedIn: Bool { MetagGateway.isSignedIn }
    var aiAllowed: Bool { isSignedIn }
    var tier: AccountTier { account?.user.tier ?? .none }
    var isPaid: Bool { tier.isPaid }

    var spentCredits: Int { account?.user.spentCreditsThisPeriod ?? 0 }
    var budgetCredits: Int? {
        guard let user = account?.user else { return nil }
        let tierBudget = account?.plan?.monthlyBudgetCredits ?? 0
        return tierBudget + (user.purchasedCredits ?? 0)
    }

    var remainingCredits: Int { metagCredits }

    func refreshMetagAccount() async {
        guard MetagGateway.isSignedIn else {
            metagCredits = 0
            return
        }
        do { metagCredits = try await MetagGateway.account().credits }
        catch { lastError = error.localizedDescription }
    }
    var hasCredits: Bool { remainingCredits > 0 }

    @ObservationIgnored private(set) var convex: ConvexClientWithAuth<String>?
    @ObservationIgnored private var accountSubscription: AnyCancellable?
    @ObservationIgnored private var plansSubscription: AnyCancellable?
    @ObservationIgnored private var authStateTask: Task<Void, Never>?
    @ObservationIgnored private var didConfigure = false
    @ObservationIgnored private var buyCreditsTask: Task<Void, Never>?

    private init() {}

    func configure() {
        guard !didConfigure else { return }
        didConfigure = true

        // METAG 自有网关取代 Clerk/Convex：登录态在 Keychain，额度在网关
        isMisconfigured = false
        isLoading = false
        Task { await refreshMetagAccount() }
    }

    private func startAuthObservation() {
        guard let convex else { return }
        authStateTask = Task { @MainActor [weak self] in
            // Wait for Clerk to restore any cached session first.
            for _ in 0..<50 where !Clerk.shared.isLoaded {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            for await state in convex.authState.values {
                guard let self else { return }
                self.authState = state
                switch state {
                case .loading:
                    Log.account.notice("auth state loading", telemetry: "Auth state changed", data: ["state": "loading"])
                    self.isLoading = true
                case .authenticated:
                    Log.account.notice("auth state authenticated", telemetry: "Auth state changed", data: ["state": "authenticated"])
                    await self.provisionAndSubscribe()
                    self.isLoading = false
                case .unauthenticated:
                    Log.account.notice("auth state unauthenticated", telemetry: "Auth state changed", data: ["state": "unauthenticated"])
                    self.clearAccount()
                    self.isLoading = Clerk.shared.session != nil
                }
            }
        }
    }

    private func provisionAndSubscribe() async {
        guard let convex else { return }

        let user = Clerk.shared.user
        let name = [user?.firstName, user?.lastName]
            .compactMap { $0 }
            .joined(separator: " ")
        Telemetry.setUser(
            id: user?.id,
            email: user?.primaryEmailAddress?.emailAddress,
            username: name.isEmpty ? nil : name
        )
        Analytics.identifyUser(id: user?.id)
        let args: [String: ConvexEncodable?] = [
            "email": user?.primaryEmailAddress?.emailAddress,
            "name": name.isEmpty ? nil : name,
            "image": user?.imageUrl,
        ]

        for attempt in 0..<3 {
            do {
                if attempt == 0 {
                    Log.account.notice("account provision start", telemetry: "Account provision started")
                }
                try await convex.mutation("users:upsertFromAuth", with: args)
                Log.account.notice(
                    "account provision ok attempt=\(attempt + 1)",
                    telemetry: "Account provision finished",
                    data: ["attempt": attempt + 1]
                )
                break
            } catch {
                lastError = error.localizedDescription
                if attempt == 2 {
                    Log.account.warning(
                        "account provision failed error=\(error.localizedDescription)",
                        telemetry: "Account provision failed",
                        data: ["attempt": attempt + 1, "error": error.localizedDescription]
                    )
                    return
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        startAccountSubscription()
    }

    private func startPlansSubscription() {
        plansSubscription?.cancel()
        plansSubscription = convex?
            .subscribe(to: "billing:listPlans", yielding: [AvailablePlan].self)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let err) = completion {
                        Log.account.warning(
                            "plans subscription failed error=\(err.localizedDescription)",
                            telemetry: "Account plans subscription failed",
                            data: ["error": err.localizedDescription]
                        )
                        self?.lastError = err.localizedDescription
                    }
                },
                receiveValue: { [weak self] plans in
                    self?.availablePlans = plans
                }
            )
    }

    private func startAccountSubscription() {
        accountSubscription?.cancel()
        accountSubscription = convex?
            .subscribe(to: "account:get", yielding: AccountResponse.self)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let err) = completion {
                        Log.account.warning(
                            "account subscription failed error=\(err.localizedDescription)",
                            telemetry: "Account subscription failed",
                            data: ["error": err.localizedDescription]
                        )
                        self?.lastError = err.localizedDescription
                    }
                },
                receiveValue: { [weak self] response in
                    self?.account = response
                    self?.lastError = nil
                    Analytics.identifyUser(
                        id: Clerk.shared.user?.id,
                        properties: ["tier": response.user.tier.rawValue]
                    )
                }
            )
    }

    private func clearAccount() {
        Telemetry.setUser(id: nil)
        Analytics.resetUser()
        accountSubscription?.cancel()
        accountSubscription = nil
        buyCreditsTask?.cancel()
        buyCreditsTask = nil
        account = nil
        isBuyingCredits = false
    }

    func signInWithGoogle() async { await signIn(with: .google) }

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
        account = nil
    }

    func subscribe(tier: AccountTier) async {
        await openCheckout(plan: "sub")
    }

    func buyCredits(dollars: Int) {
        guard !isBuyingCredits else { return }
        isBuyingCredits = true
        buyCreditsTask = Task { @MainActor [weak self] in
            defer {
                self?.isBuyingCredits = false
                self?.buyCreditsTask = nil
            }
            await self?.openCheckout(plan: "pack")
        }
    }

    private func openCheckout(plan: String) async {
        lastError = nil
        do { openInBrowser(try await MetagGateway.checkoutURL(plan: plan)) }
        catch { lastError = error.localizedDescription }
    }

    func sendFeedback(
        message: String,
        email: String?,
        mayContact: Bool,
        screenshotPngBase64: String?,
        appVersion: String,
        osVersion: String
    ) async throws {
        guard let convex else {
            throw NSError(
                domain: "Palmier.Feedback",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Backend not configured."]
            )
        }
        var args: [String: ConvexEncodable?] = [
            "message": message,
            "mayContact": mayContact,
            "appVersion": appVersion,
            "osVersion": osVersion,
        ]
        if let email { args["email"] = email }
        if let screenshotPngBase64 { args["screenshotPngBase64"] = screenshotPngBase64 }
        let _: OkResponse = try await convex.action("feedback:send", with: args)
    }

    func manageSubscription() async {
        lastError = nil
        guard let convex else { return }
        do {
            let result: UrlResponse = try await convex.action(
                "billing:createPortalSession"
            )
            openInBrowser(result.url)
        } catch {
            lastError = error.localizedDescription
        }
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
    var displayPrimaryText: String {
        if !isSignedIn { return L10n.string("Signed out") }
        let user = account?.user
        return user?.displayName ?? user?.email ?? L10n.string("Signed in")
    }

    var displaySecondaryText: String? {
        guard isSignedIn else { return nil }
        let user = account?.user
        return user?.displayName != nil ? user?.email : nil
    }

    var displayInitial: String {
        guard isSignedIn else { return "" }
        let user = account?.user
        let source = user?.displayName ?? user?.email ?? ""
        return source.first.map { String($0).uppercased() } ?? ""
    }

    func availablePlan(for tier: AccountTier) -> AvailablePlan? {
        availablePlans.first { $0.tier == tier }
    }
}
