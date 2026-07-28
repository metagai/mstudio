import SwiftUI

/// The gateway reports an absolute credit balance, not a period budget, so there is no
/// denominator to draw a progress bar against — show the balance itself.
struct CreditSummaryView: View {
    enum Style {
        case full    // settings
        case compact // generation panel header chip
    }

    let style: Style
    @Bindable private var account = AccountService.shared
    @State private var showActions = false

    var body: some View {
        if account.isSignedIn {
            switch style {
            case .full:
                fullView
            case .compact:
                Button {
                    showActions = true
                } label: {
                    compactView
                }
                .buttonStyle(.plain)
                .help(L10n.string("Manage credits"))
                .popover(isPresented: $showActions, arrowEdge: .bottom) {
                    CreditActionsPopover(isPresented: $showActions)
                }
            }
        }
    }

    private var credits: Int { account.remainingCredits }

    private var fullView: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.xs) {
            Text(credits.formatted())
                .font(.system(size: AppTheme.FontSize.xl, weight: AppTheme.FontWeight.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(credits == 1 ? L10n.key("credit") : L10n.key("credits"))
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
            Spacer(minLength: 0)
        }
    }

    private var compactView: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(tint)
            Text(credits.formatted())
                .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.medium))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xs)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(
            Capsule().stroke(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.hairline)
        )
        .fixedSize(horizontal: true, vertical: false)
        .help(L10n.string("\(credits.formatted()) credits remaining"))
    }

    /// A drained balance is alarming; thresholds are absolute because there is no budget.
    private var tint: Color {
        switch credits {
        case ..<1: return .red
        case ..<20: return .orange
        default: return AppTheme.Accent.primary
        }
    }
}

private struct CreditActionsPopover: View {
    @Bindable private var account = AccountService.shared
    @Binding var isPresented: Bool

    private static let popoverWidth: CGFloat = 240

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            Text(L10n.key("Add credits"))
                .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(AppTheme.Text.tertiaryColor)

            CreditPackButton()

            Button {
                SettingsWindowController.shared.show(tab: .account)
                isPresented = false
            } label: {
                Text(L10n.key("Account settings")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.capsule(.secondary))
            .controlSize(.small)

            if let error = account.lastError {
                Text(error)
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppTheme.Spacing.md)
        .frame(width: Self.popoverWidth)
    }
}

/// Buys the one-off credit pack priced by `/api/v1/pricing`. The amount and the credits
/// are never computed locally — the gateway checkout is what actually charges.
struct CreditPackButton: View {
    @Bindable private var account = AccountService.shared
    var fill: AnyShapeStyle?
    var showsExternalLinkIcon: Bool = false

    var body: some View {
        if let pack = account.creditPack {
            Button {
                account.buyCreditPack()
            } label: {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Text(L10n.string("Buy \(pack.credits.formatted()) credits · $\(String(format: "%.2f", pack.price_usd))"))
                    if showsExternalLinkIcon {
                        Image(systemName: "arrow.up.right")
                            .font(.system(
                                size: AppTheme.FontSize.xs,
                                weight: AppTheme.FontWeight.semibold
                            ))
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.capsule(.secondary, size: .small, fill: fill))
            .disabled(account.isBuyingCredits)
            .pointerStyle(.link)
        }
    }
}
