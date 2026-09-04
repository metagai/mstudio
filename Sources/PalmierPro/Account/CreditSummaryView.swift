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

    /// 余额那一格的**四种语气**。
    ///
    /// 抽成纯函数是因为上一版把「不知道」和「零」画成了同一样东西：
    /// `metagCredits` 初值是 0，`tint` 的第一档是 `..<1 → .red`。
    /// 于是登录之后、余额答上来之前的那一秒（从国内打网关一个来回一秒多），
    /// 以及**任何一次失败的刷新之后**，屏幕上是一个刺眼的红 0 ——
    /// 在告诉他"你没钱了，出不了片"。**不知道不是零。**
    enum Tone: Equatable { case unknown, empty, low, normal }

    nonisolated static func tone(credits: Int, known: Bool) -> Tone {
        guard known else { return .unknown }
        switch credits {
        case ..<1: return .empty
        case ..<20: return .low
        default: return .normal
        }
    }

    /// 屏幕上写的那几个字。不知道的时候写破折号，不写 0。
    nonisolated static func amount(credits: Int, known: Bool) -> String {
        known ? credits.formatted() : "—"
    }

    private var amount: String { Self.amount(credits: credits, known: account.creditsKnown) }

    private var fullView: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.xs) {
            Text(verbatim: amount)
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
            Text(verbatim: amount)
                .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.medium))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(.horizontal, AppTheme.Spacing.smMd)
        .padding(.vertical, AppTheme.Spacing.xs)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(
            Capsule().stroke(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.hairline)
        )
        .fixedSize(horizontal: true, vertical: false)
        .help(account.creditsKnown
              ? L10n.string("\(credits.formatted()) credits remaining")
              : L10n.string("Checking your balance…"))
    }

    /// A drained balance is alarming; thresholds are absolute because there is no budget.
    private var tint: Color {
        switch Self.tone(credits: credits, known: account.creditsKnown) {
        case .unknown: return AppTheme.Text.tertiaryColor
        case .empty: return .red
        case .low: return .orange
        case .normal: return AppTheme.Accent.primary
        }
    }
}

private struct CreditActionsPopover: View {
    @Bindable private var account = AccountService.shared
    @Binding var isPresented: Bool

    private static let popoverWidth: CGFloat = 240

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            Text(L10n.string("Add credits"))
                .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(AppTheme.Text.tertiaryColor)

            CreditPackButton()

            Button {
                SettingsWindowController.shared.show(tab: .account)
                isPresented = false
            } label: {
                Text(L10n.string("Account settings")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.capsule(.secondary))
            .controlSize(.small)

            if let error = account.lastError {
                Text(error)
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Status.errorColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppTheme.Spacing.mdLg)
        .frame(width: Self.popoverWidth)
    }
}

/// Buys the one-off credit pack priced by `/api/v1/pricing`. The amount and the credits
/// are never computed locally — the gateway checkout is what actually charges.
struct CreditPackButton: View {
    @Bindable private var account = AccountService.shared
    var fill: AnyShapeStyle?
    var showsExternalLinkIcon: Bool = false

    /// **按钮永远在。** 上一版是 `if let pack = account.creditPack` ——
    /// 报价单没拉到，这个产品唯一的付钱入口就整个消失，不留一句话。
    /// 价钱是**标签**，不是**许可**：不知道价钱就先不写价钱，
    /// 按下去的时候现拉（见 `buyCreditPack()`）。
    var body: some View {
        Button {
            account.buyCreditPack()
        } label: {
            HStack(spacing: AppTheme.Spacing.xs) {
                if let pack = account.creditPack {
                    Text(L10n.string("Buy \(pack.credits.formatted()) credits · $\(String(format: "%.2f", pack.price_usd))"))
                } else {
                    Text(L10n.string("Buy credits"))
                }
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
