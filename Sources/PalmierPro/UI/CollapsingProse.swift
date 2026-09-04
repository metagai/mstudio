import SwiftUI

/// 一段可能很长的用户文字。**默认收起，要看再展开。**
///
/// ## 为什么
///
/// 2026-09-01 创始人在 web 端粘了一段两千字的 prompt 点生成，看到的是：
/// 片子被挤成顶上一条，**整屏是他自己刚粘进去的那段字**。
///
/// **那一刻 prompt 变成了页面本身。** 写那一版的人假设 prompt 是一句话 ——
/// 而这个产品的第一屏就写着"写一句话"，所以这个假设当时是对的。
/// 用户粘一份剧本进来，它就不对了，而没有任何东西会报错：
/// 布局照常渲染，只是把主角挤没了。
///
/// Mac 上同一个形状在检视器里：生成过的片段会把 prompt 原样铺出来，
/// `fixedSize(vertical:)` 且没有行数上限 —— 在一条窄侧栏里，
/// 两千字就是一根一里长的柱子，把下面所有东西推出屏幕。
///
/// **用户写的东西长度不可控，是产品的常态，不是异常。** 所以凡是把
/// 用户文字显示回去的地方，都要先问"最长会有多长"。
struct CollapsingProse: View {
    let text: String
    /// 收起时给几行。四行足够认出"这是我写的那段"，又不至于占掉整块面板。
    var collapsedLines = 4

    @State private var expanded = false

    /// 短到本来就放得下的，不给多余的控件 —— 一颗永远不用点的按钮是噪音。
    private var needsToggle: Bool {
        text.count > collapsedLines * 40 || text.contains("\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(verbatim: text)
                .font(.system(size: AppTheme.FontSize.sm))
                .lineSpacing(AppTheme.Spacing.xs)
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .textSelection(.enabled)
                .lineLimit(expanded ? nil : collapsedLines)
                .fixedSize(horizontal: false, vertical: true)

            if needsToggle {
                Button(expanded ? L10n.string("Show less") : L10n.string("Show more")) {
                    withAnimation(.easeOut(duration: AppTheme.Anim.transition)) { expanded.toggle() }
                }
                .buttonStyle(.plain)
                .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(AppTheme.Accent.brand)
            }
        }
    }
}
