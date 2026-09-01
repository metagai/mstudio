import SwiftUI

struct OnboardingOverlay: View {
    @Bindable var onboarding: OnboardingStore

    @Bindable private var account = AccountService.shared
    @State private var signInFailed = false

    var body: some View {
        ZStack {
            AppTheme.MediaOverlay.backgroundColor.opacity(AppTheme.Opacity.strong)
                .ignoresSafeArea()
            card
                .frame(
                    width: AppTheme.Onboarding.cardWidth,
                    height: AppTheme.Onboarding.cardHeight
                )
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: AppTheme.Anim.transition), value: onboarding.step)
    }

    private var card: some View {
        VStack(spacing: AppTheme.Spacing.zero) {
            cardContent
            footer
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .padding(.vertical, AppTheme.Spacing.lgXl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.mdLg, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.mdLg, style: .continuous)
                        .strokeBorder(
                            AppTheme.Border.primaryColor,
                            lineWidth: AppTheme.BorderWidth.hairline
                        )
                }
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.mdLg, style: .continuous))
        .shadow(AppTheme.Shadow.lg)
    }

    @ViewBuilder
    private var cardContent: some View {
        let content = stepContent
            .id(onboarding.step)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, AppTheme.Spacing.xxl)
            .padding(.top, AppTheme.Spacing.xxl)
            .padding(.bottom, contentBottomPadding)
        if onboarding.step == .discovery || onboarding.step == .account {
            ScrollView { content }
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            content
                .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch onboarding.step {
        case .welcome:
            OnboardingWelcomeStep()
        case .discovery:
            OnboardingQuestionnaireStep(
                onboarding: onboarding,
                title: L10n.string("Quick questions"),
                questions: OnboardingQuestion.discoveryQuestions
            )
        case .profile:
            OnboardingQuestionnaireStep(
                onboarding: onboarding,
                title: L10n.string("Tell us about your work"),
                questions: OnboardingQuestion.profileQuestions
            )
        case .account:
            OnboardingAccountStep(
                account: account,
                sampleState: onboarding.sampleState,
                signInFailed: signInFailed
            )
        }
    }

    private var footer: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            if onboarding.step != .welcome {
                secondaryButton(L10n.string("Back"), action: onboarding.goBack)
            }
            Spacer()
            switch onboarding.step {
            case .welcome:
                primaryButton(L10n.string("Continue"), action: onboarding.advance)
            case .discovery:
                primaryButton(L10n.string("Continue"), action: onboarding.advance)
            case .profile:
                primaryButton(L10n.string("Continue"), action: onboarding.submitSurvey)
            case .account:
                // **主按钮是"先看一眼"，不是"先登录"。**
                // 8/29 起 1112 个人落地、0 个人打过一行字 —— 而他们在这一屏
                // 看到的最响的一句话是"用 Google 登录"。他刚下完一个安装包，
                // 比网页访客更有耐心，但这不构成让他先交身份的理由。
                // 陌生人本来就能建草案（网关放行），墙在"想出片"那一步。
                accountAction
            }
        }
    }

    private var contentBottomPadding: CGFloat {
        switch onboarding.step {
        case .profile, .discovery:
            AppTheme.Spacing.md
        case .welcome, .account:
            AppTheme.Spacing.xxl
        }
    }

    @ViewBuilder
    private var accountAction: some View {
        if !account.isSignedIn && !account.isMisconfigured {
            // 没登录：让他直接去写那一句。登录降为次要 ——
            // 它仍然在，只是不再是他见到的第一件事。
            primaryButton(L10n.string("See your film first"), action: startDraft)
            // 四种都给。**Apple 排第一** —— 在 Mac 上它是"这个 app 属于这台电脑"
            // 的信号；微信对国内用户是唯一顺手的那个。
            HStack(spacing: AppTheme.Spacing.xs) {
                ForEach(MetagAuth.Provider.allCases, id: \.self) { provider in
                    secondaryButton(
                        provider.title,
                        action: { signIn(with: provider) },
                        disabled: account.isSigningIn
                    )
                }
            }
            // 赠额挂在登录按钮旁边 —— **它是登录的理由，不是打开 app 的理由。**
            // 数字取自网关的 signup_free_credits；取不到就不提数字，
            // 宁可少说一句也不要说错一个数。
            if let grant = account.signupFreeCredits {
                Text(L10n.string("\(grant.formatted()) free credits when you sign in"))
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Text.mutedColor)
            }
        } else if account.isSignedIn || account.isMisconfigured {
            primaryButton(
                onboarding.sampleState == .loading ? L10n.string("Loading…") : L10n.string("Tutorial"),
                action: onboarding.openSampleProject
            )
        }
    }

    private func primaryButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.capsule(.prominent, size: .regular))
            .keyboardShortcut(.defaultAction)
            .disabled(isBusy)
    }

    /// 关掉引导，直接把草案面板端到他面前。
    private func startDraft() {
        onboarding.skip()
        NotificationCenter.default.post(name: .metagStartDraft, object: nil)
    }

    private func secondaryButton(
        _ label: String,
        action: @escaping () -> Void,
        disabled: Bool? = nil
    ) -> some View {
        Button(label, action: action)
            .buttonStyle(.capsule(
                .secondary,
                size: .regular,
                fill: AnyShapeStyle(AppTheme.Onboarding.secondaryButtonFill)
            ))
            .disabled(disabled ?? isBusy)
    }

    private var isBusy: Bool {
        account.isSigningIn || onboarding.sampleState == .loading
    }

    private func signIn(with provider: MetagAuth.Provider) {
        Task {
            signInFailed = false
            await account.signIn(with: provider)
            signInFailed = !account.isSignedIn && account.lastError != nil
        }
    }
}
