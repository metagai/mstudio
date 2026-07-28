import SwiftUI

/// Shared grid-tile chrome: artwork, selection border, name row with rename, clicks, context menu.
struct MediaTileScaffold<Artwork: View, MenuItems: View>: View {
    let name: String
    let isSelected: Bool
    var isDropHover: Bool = false
    var showsActiveDot: Bool = false
    @Binding var isRenaming: Bool
    let onTap: () -> Void
    let onOpen: () -> Void
    let onCommitRename: (String) -> Void
    let onCancelRename: () -> Void
    @ViewBuilder let artwork: () -> Artwork
    @ViewBuilder let menuItems: () -> MenuItems

    @State private var lastClickTime: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            ZStack { artwork() }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                )
                .contentShape(Rectangle())

            nameRow
                .padding(.horizontal, AppTheme.Spacing.xs)
                .padding(.vertical, AppTheme.Spacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                        .fill(isRenaming ? AppTheme.Text.primaryColor.opacity(AppTheme.Opacity.faint) : .clear)
                )
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { handleClick() }
        .contextMenu { menuItems() }
    }

    @ViewBuilder
    private var nameRow: some View {
        if isRenaming {
            InlineRenameField(
                originalName: name,
                onCommit: onCommitRename,
                onCancel: onCancelRename
            )
        } else {
            HStack(spacing: AppTheme.Spacing.xs) {
                if showsActiveDot {
                    Circle()
                        .fill(AppTheme.Accent.primary)
                        .frame(width: AppTheme.Spacing.xs, height: AppTheme.Spacing.xs)
                }
                Text(name)
                    .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(AppTheme.Text.primaryColor)
            }
        }
    }

    private var borderColor: Color {
        if isDropHover { return AppTheme.Accent.primary.opacity(AppTheme.Opacity.prominent) }
        if isSelected { return AppTheme.Accent.primary }
        return Color.clear
    }

    private var borderWidth: CGFloat {
        isDropHover || isSelected ? AppTheme.BorderWidth.thick : 0
    }

    private func handleClick() {
        let now = Date()
        if let last = lastClickTime, now.timeIntervalSince(last) < NSEvent.doubleClickInterval {
            onOpen()
            lastClickTime = nil
        } else {
            onTap()
            lastClickTime = now
        }
    }
}

extension View {
    func tileBadge() -> some View {
        // 角标压在【任意亮度的媒体缩略图】上。原先靠 .ultraThinMaterial 当底，
        // 解除 darkAqua 后它变成亮玻璃，白字当场不可读。
        // 改成固定的深色遮罩 + 浅色字 —— 这样与主题、与素材亮度都无关。
        foregroundStyle(AppTheme.Text.onDarkColor)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xxs)
            .background(Color.black.opacity(AppTheme.Opacity.strong), in: .capsule)
            .padding(AppTheme.Spacing.xs)
    }
}
