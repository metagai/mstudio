import SwiftUI

struct SidebarRowButton: View {
    let label: String
    let systemImage: String
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SidebarRowLabel(label: L10n.string(key: label), systemImage: systemImage)
                .hoverHighlight(cornerRadius: AppTheme.Radius.xl, isActive: isSelected)
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// 侧栏一行的**样子**。按钮和菜单共用它。
///
/// 分出来是因为侧栏底部原来是**两种控件并排**：登录是个 `Menu`
/// （系统自带的小箭头、自己的高亮、`mdLg` 的左边距），设置是 `SidebarRowButton`
/// （`smMd` 的左边距、我们的悬停高亮）。**两行字对不齐，两种高亮，一个有箭头一个没有**
/// —— 单独看每一行都正常，并排看就是"这两行不是一套东西"。
///
/// 一行的样子只有一处，两边就不会各自漂。
struct SidebarRowLabel: View {
    let label: String
    let systemImage: String

    var body: some View {
        HStack(spacing: AppTheme.Spacing.smMd) {
            Image(systemName: systemImage)
                .font(.system(size: AppTheme.FontSize.md))
                .frame(width: AppTheme.IconSize.sm)
            Text(verbatim: label)
                .font(.system(size: AppTheme.FontSize.mdLg, weight: AppTheme.FontWeight.regular))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.Spacing.mdLg)
        .padding(.vertical, AppTheme.Spacing.smMd)
        .foregroundStyle(AppTheme.Text.primaryColor)
    }
}
