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
                .padding(.vertical, AppTheme.Spacing.lg)
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
            // **登录那四颗另起一行。**
            //
            // 它们原来跟"上一步""先看一眼"挤在同一个 `HStack` 里 ——
            // 六颗按钮加一句赠额文字塞进一行放不下，于是 provider 按钮被压到最窄，
            // 字一个一个往下折：WeC/hat、App/le、Goo/gle、Git/Hub。
            // 2026-09-02 创始人装完真机截图照出来的，而这一屏是他看到的第一样东西。
            // **它排在动作行之前。**
            //
            // 原来夹在动作行和出口之间，于是「返回」正好贴在这四颗上面 ——
            // 读起来像「返回 / WeChat / Apple / Google / GitHub」是一组，
            // 而它们是两件完全不同的事。
            // 现在是：先摆出他此刻能做的选择（登录，或者直接去看片子），
            // **导航（返回）和出路（以后再说）留在下面。**
            if onboarding.step == .account {
                accountSignIn
                    .padding(.bottom, AppTheme.Spacing.xs)
            }



            HStack(spacing: AppTheme.Spacing.smMd) {
                // 第一步没有"上一步"。**按序号判，不按某一步的名字判** ——
                // 名字会被删掉（`welcome` 就是），而"第一步"这个概念不会。
                if onboarding.step.rawValue > 0 {
                    secondaryButton(L10n.string("Back"), action: onboarding.goBack)
                }
                Spacer()
                switch onboarding.step {
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

            // 看片这一屏现在排在问卷前面，所以它不再是最后一屏 ——
            // 不动手的人得有一条往下走的路。
            //
            // **它是次要的、小的、在最下面**：这一屏的主角是"先看一眼"，
            // 而一颗和主按钮一样重的"跳过"会把两条路变成一道选择题。
            // **出路不该因为他登录了就消失。**
            if OnboardingStore.showsSkip(step: onboarding.step,
                                         signedIn: account.isSignedIn,
                                         misconfigured: account.isMisconfigured) {
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
            AppTheme.Spacing.mdLg
        case .account:
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
            // **他刚交出了今天最大的一笔成本（自己的身份）。**
            // 上一版换给他的是一颗"下载教程"的按钮 —— 代价付了，价值一点没拿到，
            // 而下载失败还会把他锁在这张卡里。
            // 主按钮对所有人都是同一句：先看一眼你自己的片子。
            primaryButton(L10n.string("See your film first"), action: startDraft)
        }
    }

    /// 登录那一块：一句话 + 四颗按钮。**次要，所以在下面、小一号。**
    @ViewBuilder
    private var accountSignIn: some View {
        if account.isSignedIn || account.isMisconfigured {
            // 已经登录的人：主按钮是"先看一眼你的片子"，
            // **教程降成一条安静的次要入口** —— 想要的人有，不想要的人不挡路。
            // （上一版它是登录之后唯一的按钮，而它失败时会把人锁在这张卡里。）
            Button(onboarding.sampleState == .loading
                   ? L10n.string("Loading…") : L10n.string("Open the tutorial project"),
                   action: onboarding.openSampleProject)
                .buttonStyle(.plain)
                .font(.system(size: AppTheme.FontSize.xs))
                .foregroundStyle(AppTheme.Accent.brand)
                .disabled(isBusy)
        } else if !account.isSignedIn && !account.isMisconfigured {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                // 赠额是**登录的理由**，不是打开 app 的理由，所以它领着这一块，
                // 不再吊在按钮右边。数字取自网关的 signup_free_credits；
                // 取不到就不提数字 —— 宁可少说一句，也不要说错一个数。
                //
                // **但"少说一句"不能变成"什么都不说"。**
                // 上一版整句话都挂在 `if let grant` 里：网关那一格取不到
                // （首屏那一刻多半还没回来，国内更慢），
                // 底下四颗 WeChat / Apple / Google / GitHub 就**一句说明都没有** ——
                // 新用户看到的第二屏上四颗没头没尾的按钮。
                // 又是「把不知道画成事实」最坏的那一种：**说明无声消失。**
                //
                // 所以：那句话永远在，数字是它的**补充**。
                Text(verbatim: Self.signInReason(grant: account.signupFreeCredits))
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Text.mutedColor)
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

    /// 那四颗登录按钮上面那句话。**它永远在，数字只是补充。**
    ///
    /// 判据直接问它：`grant` 为 nil 时那句话不许是空的。
    @MainActor
    static func signInReason(grant: Int?) -> String {
        grant.map {
            L10n.string("Sign in and your films follow you — \($0.formatted()) free credits to start")
        } ?? L10n.string("Sign in and your films follow you")
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
