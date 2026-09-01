import SwiftUI

/// Compact account summary shown when the user clicks the IdentityStrip avatar.
struct AccountPopoverCard: View {
    @Bindable private var account = AccountService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showCredits = false

    private static let cardWidth: CGFloat = 280

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            identityBlock

            if account.isSignedIn {
                Divider().overlay(AppTheme.Border.subtleColor)
                planBlock
            }

            Divider().overlay(AppTheme.Border.subtleColor)
            footerRow

            if let error = account.lastError {
                Text(error)
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Status.errorColor)
            }
        }
        .padding(AppTheme.Spacing.md)
        .frame(width: Self.cardWidth)
        .focusEffectDisabled()
    }

    // MARK: - Identity (mirrors IdentityStrip layout)

    private var identityBlock: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            UserAvatar(
                diameter: AppTheme.IconSize.xl,
                fontSize: AppTheme.FontSize.mdLg
            )
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(account.displayPrimaryText)
                    .font(.system(size: AppTheme.FontSize.md, weight: .medium))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Plan + credit info

    private var planBlock: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Text(account.planLabel)
                    .font(.system(size: AppTheme.FontSize.md, weight: .semibold))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Spacer(minLength: 0)
                // 点余额看流水，而不是只显示一个数字。用户最想知道的是"我的钱去哪了"，
                // 尤其在出过事之后 —— 这张表此前只写不读，他连自己被退过款都看不见。
                Button {
                    showCredits.toggle()
                } label: {
                    CreditSummaryView(style: .compact)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showCredits, arrowEdge: .bottom) {
                    MetagCreditsView()
                }
            }

            SubscriptionLine()

            if !account.isPaid {
                upgradeBlock
            }
        }
    }

    @ViewBuilder
    private var upgradeBlock: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            ForEach(account.subscriptionPlans) { plan in
                planRow(plan)
            }
        }
    }

    private func planRow(_ plan: MetagGateway.Pricing.Plan) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text("$\(plan.price_usd, specifier: "%.2f")/mo")
                .font(.system(size: AppTheme.FontSize.sm, weight: .semibold))
                .foregroundStyle(AppTheme.Text.primaryColor)
                .monospacedDigit()

            Text(creditsShortLabel(plan.credits))
                .font(.system(size: AppTheme.FontSize.xs))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
                .monospacedDigit()
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(L10n.key("Subscribe")) {
                Task { await account.subscribe(planId: plan.id) }
                dismiss()
            }
            .buttonStyle(.capsule(.secondary))
            .controlSize(.small)
        }
    }

    private func creditsShortLabel(_ credits: Int) -> String {
        if credits >= 1000, credits % 1000 == 0 {
            return L10n.string("\(credits / 1000)k credits")
        }
        return CostEstimator.localizedDescription(credits)
    }

    // MARK: - Footer (Settings + Sign in / Sign out)

    private var footerRow: some View {
        VStack(spacing: AppTheme.Spacing.xxs) {
            footerButton(label: L10n.string("Settings"), systemImage: "gearshape") {
                SettingsWindowController.shared.show()
                dismiss()
            }
            footerButton(label: L10n.key("Feedback"), systemImage: "bubble.left.and.bubble.right") {
                FeedbackMail.open()
                dismiss()
            }
            if account.isSignedIn {
                footerButton(label: L10n.string("Sign out"), systemImage: "rectangle.portrait.and.arrow.right") {
                    Task { await account.signOut() }
                    dismiss()
                }
            } else {
                // 这一行**只是打开菜单**，不直接授权。它以前一点就跳 Google。
                SignInMenu {
                    footerLabel(
                        label: account.isSigningIn ? L10n.string("Opening…") : L10n.string("Sign in"),
                        systemImage: "person.crop.circle"
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
        }
    }

    private func footerButton(label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            footerLabel(label: label, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: AppTheme.Radius.sm)
    }

    /// 按钮和菜单共用同一张脸 —— 登录那一行是菜单，其余是按钮，看上去必须一样。
    private func footerLabel(label: String, systemImage: String) -> some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: AppTheme.FontSize.smMd))
            Text(label)
                .font(.system(size: AppTheme.FontSize.sm))
            Spacer(minLength: 0)
        }
        .foregroundStyle(AppTheme.Text.secondaryColor)
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xs)
        .contentShape(Rectangle())
    }
}
