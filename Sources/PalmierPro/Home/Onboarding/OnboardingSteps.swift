import AppKit
import SwiftUI

struct OnboardingWelcomeStep: View {
    private static let hero = BundledResource.url("Images/welcome-butterfly.jpg")
        .flatMap(NSImage.init(contentsOf:))

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            OnboardingTitle(L("Welcome to METAG"))
            heroImage
            OnboardingDetail(L("A video editor built for AI. Generate, and edit all in one place."))
        }
    }

    private var heroImage: some View {
        Group {
            if let hero = Self.hero {
                Image(nsImage: hero).resizable().aspectRatio(contentMode: .fill)
            } else {
                AppTheme.aiGradient
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: AppTheme.Onboarding.welcomeHeroHeight)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
    }
}

struct OnboardingProfileStep: View {
    @Bindable var onboarding: OnboardingStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.zero) {
            OnboardingTitle(L("Tell us about your work"))
            ForEach(OnboardingQuestion.allCases) { question in
                Spacer(minLength: AppTheme.Spacing.md)
                section(question)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func section(_ question: OnboardingQuestion) -> some View {
        let selection = onboarding.selection(for: question)
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            Text(L(question.titleKey))
                .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.regular))
                .foregroundStyle(AppTheme.Text.primaryColor)
            OnboardingFlowLayout(spacing: AppTheme.Spacing.smMd) {
                ForEach(question.options) { option in
                    Button {
                        onboarding.toggle(option, for: question)
                    } label: {
                        Text(L(option.labelKey))
                            .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.regular))
                            .lineLimit(1)
                    }
                    .buttonStyle(.capsule(
                        selection.contains(option.id) ? .prominent : .secondary,
                        size: .small
                    ))
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct OnboardingFlowLayout: SwiftUI.Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: LayoutSubviews,
        cache: inout ()
    ) -> CGSize {
        arrangement(width: proposal.width ?? .greatestFiniteMagnitude, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: LayoutSubviews,
        cache: inout ()
    ) {
        for (subview, frame) in zip(subviews, arrangement(width: bounds.width, subviews: subviews).frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrangement(width: CGFloat, subviews: LayoutSubviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var cursor = CGPoint.zero
        var rowHeight: CGFloat = 0
        var contentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize.unspecified)
            let nextX = cursor.x == 0 ? 0 : cursor.x + spacing
            if nextX + size.width > width, cursor.x > 0 {
                cursor.x = 0
                cursor.y += rowHeight + spacing
                rowHeight = 0
            } else {
                cursor.x = nextX
            }
            frames.append(CGRect(origin: cursor, size: size))
            cursor.x += size.width
            rowHeight = max(rowHeight, size.height)
            contentWidth = max(contentWidth, cursor.x)
        }

        return (CGSize(width: contentWidth, height: cursor.y + rowHeight), frames)
    }
}

struct OnboardingAccountStep: View {
    @Bindable var account: AccountService
    /// 注册赠额。**取自网关的 /api/v1/pricing，不写死。**
    /// 上游那句文案写着 "250 free credits"，而我们给的是 20 ——
    /// 照抄等于在产品第一屏上许一个我们不兑现的承诺。
    @State private var freeCredits: Int?
    let sampleState: OnboardingSampleState
    let signInFailed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                OnboardingTitle(title)
                OnboardingDetail(detail)
            }
            if let failure {
                Text(failure)
                    .font(.system(size: AppTheme.FontSize.smMd))
                    .foregroundStyle(AppTheme.Status.errorColor)
            }
        }
        // 赠额来自定价端点（网关是单一真源）。取不到就不提数字 —— 见 freeCreditsLine。
        // 失败静默：引导流程不该因为一次网络抖动而报错。
        .task {
            freeCredits = try? await MetagGateway.pricing().signup_free_credits
        }
    }

    private var title: String {
        guard account.isSignedIn else {
            return L("Sign In")
        }
        // 上游取的是 Clerk 的 firstName；我们换掉了认证，只有邮箱。
        // **用邮箱的 @ 前缀当称呼**：比"欢迎"多一点人味，又不假装我们知道他叫什么。
        guard let name = account.email?.split(separator: "@").first, !name.isEmpty else {
            return L("Welcome")
        }
        return L("Welcome, %@", String(name))
    }

    private var detail: String {
        account.isSignedIn
            ? L("Watch the tutorial or start creating.")
            // **不要照抄上游的 250。** 我们的赠额是网关的 signup_free_credits
            // （当前 20），写死一个我们不给的数字，是在产品第一屏上撒谎。
            : freeCreditsLine
    }

    /// 拿不到赠额就**不提数字**。宁可少说一句，也不要说错一个数。
    private var freeCreditsLine: String {
        if let n = freeCredits, n > 0 {
            return L("Sign in to receive %@ free credits for AI chat and generation.",
                     n.formatted())
        }
        return L("Sign in to start generating.")
    }

    private var failure: String? {
        if sampleState == .failed {
            return L("Sample project couldn’t be opened. Try again.")
        }
        if signInFailed, !account.isSignedIn {
            return L("Sign-in couldn’t be completed. Try again.")
        }
        return nil
    }
}

private struct OnboardingTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: AppTheme.FontSize.title2, weight: AppTheme.FontWeight.light))
            .tracking(AppTheme.Tracking.tight)
            .foregroundStyle(AppTheme.Text.primaryColor)
    }
}

private struct OnboardingDetail: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: AppTheme.FontSize.smMd))
            .foregroundStyle(AppTheme.Text.secondaryColor)
            .fixedSize(horizontal: false, vertical: true)
    }
}
