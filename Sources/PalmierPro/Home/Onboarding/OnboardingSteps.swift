import AppKit
import SwiftUI

struct OnboardingWelcomeStep: View {
    private static let hero = BundledResource.url("Images/welcome-butterfly.jpg")
        .flatMap(NSImage.init(contentsOf:))

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            OnboardingTitle(L10n.string("Welcome to \(AppIdentity.name)"))
            heroImage
            // **第一句话要和首页说的是同一件事。**
            //
            // 原来这句是上游的定位：「A video editor built for AI」——
            // 一个"给 AI 用的视频编辑器"。而免费的 DaVinci Resolve 和刚发 4.0 的
            // OpenShot 已经把"编辑器"这条路占满了，我们在那条路上没有胜算；
            // 更要紧的是**首页说的根本不是这个**（"写一句话，METAG 分镜、配音、
            // 配乐，再把它剪成片子"）。两屏两个产品，而这一屏是他读到的第一句。
            //
            // 复用首页那句 —— 一个承诺只有一种说法，而且三语已经在了。
            OnboardingDetail(L10n.string("Write one line. METAG boards the shots, casts a voice, scores it, and cuts it together."))
        }
    }

    private var heroImage: some View {
        Group {
            if let hero = Self.hero {
                Image(nsImage: hero).resizable().aspectRatio(contentMode: .fill)
            } else {
                AppTheme.Background.raisedColor
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: AppTheme.Onboarding.welcomeHeroHeight)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
    }
}

struct OnboardingQuestionnaireStep: View {
    @Bindable var onboarding: OnboardingStore
    let title: String
    let questions: [OnboardingQuestion]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.zero) {
            OnboardingTitle(title)
            ForEach(questions) { question in
                Spacer(minLength: AppTheme.Spacing.md)
                section(question)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func section(_ question: OnboardingQuestion) -> some View {
        let selection = onboarding.selection(for: question)
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            Text(L10n.string(key: question.titleKey))
                .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.regular))
                .foregroundStyle(AppTheme.Text.primaryColor)
            OnboardingFlowLayout(spacing: AppTheme.Spacing.smMd) {
                ForEach(question.options) { option in
                    let isSelected = selection.contains(option.id)
                    Button {
                        onboarding.toggle(option, for: question)
                    } label: {
                        Text(L10n.string(key: option.labelKey))
                            .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.regular))
                            .lineLimit(1)
                    }
                    .buttonStyle(.capsule(
                        isSelected ? .prominent : .secondary,
                        size: .small,
                        fill: isSelected ? nil : AnyShapeStyle(AppTheme.Onboarding.secondaryButtonFill)
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
    }

    private var title: String {
        guard account.isSignedIn else {
            // 标题问的是他来干什么，不是我们要什么。
            return L10n.string("What do you want to film?")
        }
        // 网关只存 OAuth sub，没有可用来称呼的名字
        return L10n.string("Welcome")
    }

    private var detail: String {
        account.isSignedIn
            ? L10n.string("Watch the tutorial or start creating.")
            // 赠额的真源是网关的 signup_free_credits。取不到时不提数字 ——
            // 宁可少说一句，也不要说错一个数（我们改过赠额，写死的那句就开始骗人）。
            // **先说他能立刻得到什么，再说需要什么。**
            // 赠额那句留给"登录"那颗按钮旁边 —— 它是登录的理由，不是打开 app 的理由。
            : L10n.key("Write one line and see your film. No account needed for the first look.")
    }

    private var failure: String? {
        if sampleState == .failed {
            return L10n.string("Sample project couldn’t be opened. Try again.")
        }
        if signInFailed, !account.isSignedIn {
            return L10n.string("Sign-in couldn’t be completed. Try again.")
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
