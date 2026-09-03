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
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
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
            if showcase.films.isEmpty {
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
    }

    /// 这一行平时说"不用登录也能看一眼"，登录的时候说登录走到哪了。
    ///
    /// **空着的等待是最贵的等待。** 他扫完码从浏览器回到这一屏，如果什么都不动，
    /// 他不知道是成了、卡了、还是白扫了（2026-08-31 创始人：「过了很久才有响应」）。
    /// 换在这一行说，是因为**他的眼睛本来就在这里** —— 不必为一句状态新开一块地方。
    @ViewBuilder
    private var footnote: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
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
                Text(L10n.string("Waiting for you to finish in your browser."))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
            case .finishing:
                ProgressView().controlSize(.small)
                Text(L10n.string("Signing you in…"))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
            case .landed(let credits):
                // **最后一句说的是他拿到了什么**，不是"操作成功"。
                Image(systemName: "sparkles")
                    .foregroundStyle(AppTheme.Accent.brand)
                Text(L10n.string("You're in. \(credits.formatted()) credits are yours — enough for your first film."))
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
        HStack(spacing: AppTheme.Spacing.md) {
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
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "play.circle")
                    .font(.system(size: AppTheme.FontSize.mdLg))
                    .foregroundStyle(hovered ? AppTheme.Accent.brand : AppTheme.Text.mutedColor)
                Text(verbatim: text)
                    .font(.system(size: AppTheme.FontSize.mdLg))
                    .foregroundStyle(hovered ? AppTheme.Text.primaryColor : AppTheme.Text.secondaryColor)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
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
