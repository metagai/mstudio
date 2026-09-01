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
    private let maxWidth: CGFloat = 560

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.mdLg) {
            Text(L10n.string("What do you want to film?"))
                .font(.system(size: AppTheme.FontSize.title2, weight: .light))
                .tracking(AppTheme.Tracking.tight)
                .foregroundStyle(AppTheme.Text.primaryColor)

            HStack(spacing: AppTheme.Spacing.sm) {
                TextField(
                    // 占位符给的是**一个能直接抄的例子**，不是"请输入…"。
                    // 空着的输入框最难的一步是第一个字。
                    L10n.string("A woman in a laundromat, warm afternoon light"),
                    text: $line
                )
                .textFieldStyle(.plain)
                .font(.system(size: AppTheme.FontSize.mdLg))
                .focused($focused)
                .onSubmit(start)
                .padding(.horizontal, AppTheme.Spacing.mdLg)
                .padding(.vertical, AppTheme.Spacing.smMd)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                        .fill(AppTheme.Background.raisedColor)
                        .shadow(AppTheme.Shadow.sm)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                        .strokeBorder(
                            focused ? AppTheme.Accent.brand : AppTheme.Border.subtleColor,
                            lineWidth: focused ? AppTheme.BorderWidth.medium : AppTheme.BorderWidth.hairline
                        )
                )
                .animation(.easeOut(duration: AppTheme.Anim.hover), value: focused)

                Button(action: start) {
                    Text(busy ? L10n.string("Opening…") : L10n.string("See it"))
                        .font(.system(size: AppTheme.FontSize.mdLg, weight: AppTheme.FontWeight.semibold))
                }
                .buttonStyle(.capsule(.prominent, size: .regular))
                .disabled(busy || line.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Text(L10n.string("Free, and no account needed for the first look."))
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.mutedColor)
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
        .onAppear { focused = true }
    }

    private func start() {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        busy = true
        Task {
            await AppState.shared.startFilm(from: text)
            busy = false
        }
    }
}
