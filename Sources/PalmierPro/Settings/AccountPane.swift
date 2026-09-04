import SwiftUI

struct AccountPane: View {
    @Bindable var account = AccountService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            if account.isLoading {
                Text(L10n.string("Loading…"))
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            } else if account.isSignedIn {
                signedInBody
            } else {
                signedOutBody
            }

            if let error = account.lastError {
                Text(error)
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Status.errorColor)
            }
        }
    }

    private var signedInBody: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
            creditsSection
            subscriptionSection

            Button(L10n.string("Sign out")) {
                Task { await account.signOut() }
            }
            .buttonStyle(.capsule(.secondary, size: .regular))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var creditsSection: some View {
        SettingsGroup(title: L10n.key("Credits")) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.mdLg) {
                card {
                    cardCaption("Remaining")
                    Spacer(minLength: AppTheme.Spacing.sm)
                    CreditSummaryView(style: .full)
                    Spacer(minLength: AppTheme.Spacing.sm)
                }
                card {
                    cardCaption("Buy more")
                    CreditPackButton(
                        fill: AnyShapeStyle(AppTheme.Background.raisedColor),
                        showsExternalLinkIcon: true
                    )
                    Text(L10n.string("One-off purchase. Credits do not expire."))
                        .font(.system(size: AppTheme.FontSize.xs))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var subscriptionSection: some View {
        SettingsGroup(title: L10n.key("Subscription")) {
            HStack(alignment: .center, spacing: AppTheme.Spacing.sm) {
                Text(account.planLabel)
                    .font(.system(size: AppTheme.FontSize.md))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Spacer(minLength: 0)
            }

            // 「续到哪天」「已取消但还能用到哪天」「这个月没扣成功」——
            // 三种情况要他做的事完全不同，而在只有布尔的时候它们长得一样。
            SubscriptionLine()

            if account.subscriptionPlans.isEmpty {
                Text(L10n.string("Plans are unavailable right now."))
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            } else {
                HStack(alignment: .top, spacing: AppTheme.Spacing.mdLg) {
                    ForEach(account.subscriptionPlans) { plan in
                        planCard(plan)
                    }
                }
            }
        }
    }

    private func planCard(_ plan: MetagGateway.Pricing.Plan) -> some View {
        card {
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.xs) {
                Text("$\(plan.price_usd, specifier: "%.2f")")
                    .font(.system(size: AppTheme.FontSize.xl, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Text(L10n.string("/ month"))
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }

            Text(L10n.string("\(plan.credits.formatted()) credits / month"))
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .monospacedDigit()

            Spacer(minLength: AppTheme.Spacing.xs)

            Button {
                Task { await account.subscribe(planId: plan.id) }
            } label: {
                Text(account.isPaid ? L10n.key("Switch") : L10n.key("Subscribe")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.capsule(
                .secondary,
                size: .regular,
                fill: AnyShapeStyle(AppTheme.Background.raisedColor)
            ))
            .pointerStyle(.link)
        }
    }

    private func cardCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: AppTheme.FontSize.xs))
            .foregroundStyle(AppTheme.Text.tertiaryColor)
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.mdLg)
        .cardSurface(AppTheme.Background.prominentColor, cornerRadius: AppTheme.Radius.mdLg)
    }

    @ViewBuilder
    private var signedOutBody: some View {
        Text(L10n.string("Sign in to subscribe and use AI generation."))
            .font(.system(size: AppTheme.FontSize.sm))
            .foregroundStyle(AppTheme.Text.tertiaryColor)
            .fixedSize(horizontal: false, vertical: true)

        SignInMenu()
            .menuStyle(.button)
            .buttonStyle(.capsule(.secondary, size: .regular))
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.top, AppTheme.Spacing.xs)
    }
}
