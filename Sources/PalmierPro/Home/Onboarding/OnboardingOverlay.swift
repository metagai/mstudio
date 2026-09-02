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
                .frame(width: AppTheme.Onboarding.cardWidth)
                // **按它说的话定大小。**
                //
                // 420 是四屏共用的一个数：欢迎屏有一张 240pt 的图，撑得住；
                // 而登录屏只有标题加一行字，中间空掉一半 ——
                // 一个空出一半的对话框读起来就是"没做完"。
                // 2026-09-02 创始人真机截图上那片空白就是这么来的。
                //
                // 问卷那两屏内容可能溢出，仍然钉死高度 + 滚动。
                .frame(height: onboarding.step == .account ? nil : AppTheme.Onboarding.cardHeight)
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
        // 登录屏不再滚 —— 它现在自己贴着内容长，没有可滚的东西，
        // 而 `ScrollView` 套在一个"抱紧内容"的框里高度是没有定义的。
        if onboarding.step == .discovery {
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
        VStack(spacing: AppTheme.Spacing.xs) {
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
                    accountPrimary
                }
            }

            // **登录那四颗另起一行。**
            //
            // 它们原来跟"上一步""先看一眼"挤在同一个 `HStack` 里 ——
            // 六颗按钮加一句赠额文字塞进一行放不下，于是 provider 按钮被压到最窄，
            // 字一个一个往下折：WeC/hat、App/le、Goo/gle、Git/Hub。
            // 2026-09-02 创始人装完真机截图照出来的，而这一屏是他看到的第一样东西。
            if onboarding.step == .account { accountSignIn }

            // 看片这一屏现在排在问卷前面，所以它不再是最后一屏 ——
            // 不动手的人得有一条往下走的路。
            //
            // **它是次要的、小的、在最下面**：这一屏的主角是"先看一眼"，
            // 而一颗和主按钮一样重的"跳过"会把两条路变成一道选择题。
            if onboarding.step == .account, !account.isSignedIn, !account.isMisconfigured {
                HStack {
                    Spacer()
                    Button(L10n.string("Not now"), action: onboarding.advance)
                        .buttonStyle(.plain)
                        .font(.system(size: AppTheme.FontSize.xs))
                        .foregroundStyle(AppTheme.Text.mutedColor)
                        .disabled(isBusy)
                }
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

    /// 这一行只放**他此刻要做的那个决定**。
    @ViewBuilder
    private var accountPrimary: some View {
        if !account.isSignedIn && !account.isMisconfigured {
            // 没登录：让他直接去写那一句。登录降为次要 ——
            // 它仍然在，只是不再是他见到的第一件事。
            primaryButton(L10n.string("See your film first"), action: startDraft)
        } else if account.isSignedIn || account.isMisconfigured {
            primaryButton(
                onboarding.sampleState == .loading ? L10n.string("Loading…") : L10n.string("Tutorial"),
                action: onboarding.openSampleProject
            )
        }
    }

    /// 登录那一块：一句话 + 四颗按钮。**次要，所以在下面、小一号。**
    @ViewBuilder
    private var accountSignIn: some View {
        if !account.isSignedIn && !account.isMisconfigured {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                // 赠额是**登录的理由**，不是打开 app 的理由，所以它领着这一块，
                // 不再吊在按钮右边。数字取自网关的 signup_free_credits；
                // 取不到就不提数字 —— 宁可少说一句，也不要说错一个数。
                if let grant = account.signupFreeCredits {
                    Text(L10n.string("\(grant.formatted()) free credits when you sign in"))
                        .font(.system(size: AppTheme.FontSize.xs))
                        .foregroundStyle(AppTheme.Text.mutedColor)
                }
                // 四种都给。**Apple 排第一** —— 在 Mac 上它是"这个 app 属于这台电脑"
                // 的信号；微信对国内用户是唯一顺手的那个。
                HStack(spacing: AppTheme.Spacing.xs) {
                    ForEach(MetagAuth.Provider.ordered(), id: \.self) { provider in
                        secondaryButton(
                            provider.title,
                            action: { signIn(with: provider) },
                            disabled: account.isSigningIn
                        )
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        // **一行，不许折。** 挤到放不下时宁可让按钮自己撑开，
        // 也不要把 "WeChat" 拆成 WeC / hat 竖着排。
        Button(action: action) {
            Text(verbatim: label).lineLimit(1).fixedSize(horizontal: true, vertical: false)
        }
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
