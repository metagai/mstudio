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
    @State private var busy = false
    @FocusState private var focused: Bool

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

            VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
                ForEach(Self.starters, id: \.self) { starter in
                    StarterLine(text: starter) { start(starter) }
                        .disabled(busy)
                }
            }

            Text(L10n.string("Free, and no account needed for the first look."))
                .font(.system(size: AppTheme.FontSize.smMd))
                .foregroundStyle(AppTheme.Text.mutedColor)
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
        .onAppear { focused = true }
    }

    /// 输入框和按钮是**一个**控件。分成"方框 + 灰色药丸"看起来像张表单，
    /// 而这一屏问的是一句话。
    private var field: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            TextField(L10n.string("Describe a scene…"), text: $line)
                .textFieldStyle(.plain)
                .font(.system(size: AppTheme.FontSize.xl, weight: .light))
                .foregroundStyle(AppTheme.Text.primaryColor)
                .focused($focused)
                .onSubmit { start(line) }

            Button { start(line) } label: {
                Text(busy ? L10n.string("Opening…") : L10n.string("See it"))
            }
            .buttonStyle(.capsule(.prominent, size: .regular))
            .disabled(busy || line.trimmingCharacters(in: .whitespaces).isEmpty)
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

    private func start(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        line = text
        busy = true
        Task {
            await AppState.shared.startFilm(from: text)
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
