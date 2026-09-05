import SwiftUI

/// 首屏问的第一句话：**你想拍什么。**
///
/// 之前这里是「Welcome to METAG」加一张项目列表 —— 一个文件管理器的形状。
/// 而 8/29 起的漏斗说得很清楚：**137 个人站在 studio 的输入框前面走了，
/// 而 Mac 用户连输入框都看不到。** 一个"一句话变成片子"的产品，
/// 第一屏该是那一句话。
///
/// 按下去不弹存储面板：用他写的那句话给项目命名，直接进编辑器并把草案面板
/// 端到他面前。**他要的是片子，不是先给文件起个名。**
struct HomeHero: View {
    @State private var line = ""
    @State private var attachments: [PromptAttachment] = []
    @State private var notices: [PromptPaste.Notice] = []
    @State private var busy = false
    @FocusState private var focused: Bool

    @Bindable private var account = AccountService.shared
    @Bindable private var showcase = MetagShowcaseStore.shared
    @Bindable private var onboarding = OnboardingStore.shared
    @StateObject private var myFilms = MetagMyFilmsModel()

    /// 这一屏最宽到哪。**不铺满**：一行字横跨 1400 点没法读，
    /// 而且铺满会让它看起来像个搜索框而不是一句问话。
    private let maxWidth: CGFloat = 620

    /// 空输入框最难的一步是第一个字 —— 所以这三句是**能点的**，不是占位符里
    /// 让人照抄的样例。点一下直接开拍，这是这一屏唯一的 Aha：一次点击换一条片子。
    static var starters: [String] {
        [
            L10n.string("A woman folds laundry in an empty laundromat, warm afternoon light"),
            L10n.string("A courier bikes through Tokyo rain at night"),
            L10n.string("Two friends open a bakery in a small town"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.mdLg) {
                Text(L10n.string("What do you want to film?"))
                    .font(.system(size: AppTheme.FontSize.display, weight: .light))
                    .tracking(AppTheme.Tracking.tight)
                    .foregroundStyle(AppTheme.Text.primaryColor)

                // 先说清楚出来的是什么。**"一句话进去"之后到底出来什么**，
                // 不写在这里就得靠他自己猜。
                Text(L10n.string("Write one line. METAG boards the shots, casts a voice, scores it, and cuts it together."))
                    .font(.system(size: AppTheme.FontSize.lg))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            field

            PromptAttachmentBar(
                attachments: $attachments,
                overflow: PromptPaste.overflow(line: line, attachments: attachments),
                notices: notices
            )

            // **挪到输入框正下方。** 原来它压在三个例子底下 ——
            // 而"要不要注册、会不会扣钱"这个顾虑，是在**他手放在输入框上的那一刻**
            // 起来的，不是在他读完三个例子之后。
            footnote

            // **先给他看一条真片子。**
            //
            // 这个位置原来是三行写死的例句，点一下直接开拍 —— 那条路的 Aha
            // 隔着九十秒到两分钟，而且要花他的额度。
            // 而线上早就躺着 12 条完整样片（落地页在用），Mac 端一条没接。
            //
            // 取不到就退回那三行例句。**一个视频产品的第一屏可以少几张海报，
            // 但不能是一片空白。**
            // **他有自己的片子，就不该先看别人的。**
            //
            // 创始人：「最近的项目和 Template Lib 有待重新设计（交互不 Aha 是原罪）」。
            // 判据：**一个刚回来的创作者，零点击就能看见自己上次做的东西。**
            // 这一格是条件化的，不是新加一块 —— 那句问话照旧留着，
            // 对第一次来的人它仍然是对的主角。
            if let last = LastFilm.pick(myFilms.films) {
                LastFilm(film: last) {
                    Task {
                        await AppState.shared.openFilm(
                            jobId: last.job_id,
                            named: last.prompt ?? L10n.string("Untitled")
                        )
                    }
                }
            } else if showcase.films.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
                    ForEach(Self.starters, id: \.self) { starter in
                        StarterLine(text: starter) { start(starter) }
                            .disabled(busy)
                    }
                }
            } else {
                MetagShowcaseStrip(films: showcase.films)
            }
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
        .onAppear {
            focused = true
            showcase.loadOnce()
        }
        // **引导层一关，光标就在他面前闪。**
        //
        // `onAppear` 早在引导层还盖着的时候就跑过了 —— 那一刻 focus 给不到
        // 一个被遮住的输入框。引导结束之后不接回来的话，
        // 他按完「先看一眼你的片子」看到的是一屏静止的东西，还得自己去点输入框。
        .onChange(of: onboarding.isComplete) { _, done in
            if done { focused = true }
        }
        // 没登录就不问 —— 问了也只会拿到 401，而那会在日志里长得像故障。
        .task(id: account.isSignedIn) {
            guard account.isSignedIn else { return }
            await myFilms.load()
        }
    }

    /// 这一行平时说"不用登录也能看一眼"，登录的时候说登录走到哪了。
    ///
    /// **空着的等待是最贵的等待。** 他扫完码从浏览器回到这一屏，如果什么都不动，
    /// 他不知道是成了、卡了、还是白扫了（2026-08-31 创始人：「过了很久才有响应」）。
    /// 换在这一行说，是因为**他的眼睛本来就在这里** —— 不必为一句状态新开一块地方。
    @ViewBuilder
    private var footnote: some View {
        HStack(spacing: AppTheme.Spacing.smMd) {
            switch account.signInPhase {
            case .idle:
                // **和草案面板上那句同一个长相。** 那边是 `checkmark.seal` + 成功绿，
                // 这边原来是整屏最小最灰的字 —— 同一句承诺两种说法，
                // 而这一句是他决定要不要开始之前唯一要问的那个问题的答案。
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(AppTheme.Status.successColor)
                Text(L10n.string("Free, and no account needed for the first look."))
                    .foregroundStyle(AppTheme.Status.successColor)
            case .waiting:
                ProgressView().controlSize(.small)
                Text(verbatim: account.signInPhase.message ?? "")
                    .foregroundStyle(AppTheme.Text.secondaryColor)
            case .slow:
                // **卡住的时候不能什么都不说。**
                //
                // 回调靠浏览器跳 `metag://` 送回来。网差时那一跳可能根本不到，
                // 而**服务端那边可能已经登录成功了** —— 他在浏览器里看到"已授权"，
                // 在这儿看到一个永远转下去的圈。
                //
                // 不说"失败了"（我们不知道），也不再说"正在等你" （他已经做完了）。
                // 说实话 + 给一条真出路：重开一次多半直接就过，
                // 因为浏览器里那个会话还在，不用再扫一次码。
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                Text(verbatim: account.signInPhase.message ?? "")
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                Button(L10n.string("Open again")) {
                    guard let provider = account.lastSignInProvider else { return }
                    account.retrySignIn(with: provider)
                }
                .buttonStyle(.plain)
                .font(.system(size: AppTheme.FontSize.smMd, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(AppTheme.Accent.brand)
                .pointerStyle(.link)
            case .finishing:
                ProgressView().controlSize(.small)
                Text(verbatim: account.signInPhase.message ?? "")
                    .foregroundStyle(AppTheme.Text.secondaryColor)
            case .landed(let credits):
                // **最后一句说的是他拿到了什么**，不是"操作成功"。
                Image(systemName: "sparkles")
                    .foregroundStyle(AppTheme.Accent.brand)
                Text(verbatim: account.signInPhase.message ?? "")
                    .foregroundStyle(AppTheme.Text.primaryColor)
            }
        }
        .font(.system(size: AppTheme.FontSize.smMd))
        .animation(.easeOut(duration: AppTheme.Anim.transition), value: account.signInPhase)
    }

    /// 输入框和按钮是**一个**控件。分成"方框 + 灰色药丸"看起来像张表单，
    /// 而这一屏问的是一句话。
    /// 有话可送就能开拍 —— **一句话，或者一份稿子，都算。**
    private var canStart: Bool {
        !PromptPaste.composed(line: line, attachments: attachments).isEmpty
            && PromptPaste.overflow(line: line, attachments: attachments) == nil
    }

    private var field: some View {
        HStack(spacing: AppTheme.Spacing.mdLg) {
            TextField(L10n.string("Describe a scene…"), text: $line)
                .textFieldStyle(.plain)
                .font(.system(size: AppTheme.FontSize.xl, weight: .light))
                .foregroundStyle(AppTheme.Text.primaryColor)
                .focused($focused)
                .onSubmit { start(line) }
                // 复制一个文本文件（或一大段字）粘进来 —— 收成卡片，
                // 别把这一行撑成两千字。
                .promptPaste(isFocused: focused) { paste() }

            Button { start(line) } label: {
                Text(busy ? L10n.string("Opening…") : L10n.string("See it"))
            }
            .buttonStyle(.capsule(.prominent, size: .regular))
            .disabled(busy || !canStart)
        }
        .padding(.leading, AppTheme.Spacing.xl)
        .padding(.trailing, AppTheme.Spacing.smMd)
        .padding(.vertical, AppTheme.Spacing.smMd)
        .background(
            Capsule(style: .continuous)
                .fill(AppTheme.Background.raisedColor)
                .shadow(AppTheme.Shadow.md)
        )
        .overlay(
            // 聚焦时是一圈**柔和**的品牌色，不是 2 点粗的实线绿框 ——
            // 后者把这一屏拉回了"网页表单"的观感。
            Capsule(style: .continuous)
                .strokeBorder(
                    focused
                        ? AppTheme.Accent.brand.opacity(AppTheme.Opacity.strong)
                        : AppTheme.Border.subtleColor,
                    lineWidth: AppTheme.BorderWidth.thin
                )
        )
        .animation(.easeOut(duration: AppTheme.Anim.hover), value: focused)
    }

    /// 收下了返回 true —— 那样这次 ⌘V 就不再往输入框里粘一遍。
    private func paste() -> Bool {
        let outcome = PromptPaste.read(existing: attachments)
        guard !outcome.attachments.isEmpty || !outcome.notices.isEmpty else { return false }
        apply(outcome)
        return true
    }

    /// 拖进来和粘进来落**同一张卡** —— 两个入口给出不同的结果，
    /// 而用户并不知道自己刚才用的是哪一个。
    private func apply(_ outcome: PromptPaste.Outcome) {
        attachments.append(contentsOf: outcome.attachments)
        if let text = outcome.insert { line += text }
        notices = outcome.notices
    }

    private func start(_ text: String) {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 卡片里的稿子和他打的那一句一起送出去 —— 卡片是纯界面，
        // 接口那一侧还是一个 prompt。
        let prompt = PromptPaste.composed(line: typed, attachments: attachments)
        guard !prompt.isEmpty, !busy,
              PromptPaste.overflow(line: typed, attachments: attachments) == nil else { return }
        line = typed
        busy = true
        Task {
            await AppState.shared.startFilm(from: prompt, assets: PromptPaste.images(in: attachments))
            busy = false
        }
    }
}

private struct StarterLine: View {
    let text: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.mdLg) {
                Image(systemName: "play.circle")
                    .font(.system(size: AppTheme.FontSize.mdLg))
                    .foregroundStyle(hovered ? AppTheme.Accent.brand : AppTheme.Text.mutedColor)
                Text(verbatim: text)
                    .font(.system(size: AppTheme.FontSize.mdLg))
                    .foregroundStyle(hovered ? AppTheme.Text.primaryColor : AppTheme.Text.secondaryColor)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppTheme.Spacing.mdLg)
            .padding(.vertical, AppTheme.Spacing.smMd)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(AppTheme.Text.primaryColor.opacity(hovered ? AppTheme.Opacity.subtle : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: AppTheme.Anim.hover), value: hovered)
    }
}
