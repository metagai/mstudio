import SwiftUI

struct HoverHighlight: ViewModifier {
    var cornerRadius: CGFloat = AppTheme.Radius.sm
    var isActive: Bool = false
    var activeFill: Color?

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { isHovered = isEnabled && $0 }
            .animation(.easeOut(duration: AppTheme.Anim.hover), value: isHovered)
            .animation(.easeOut(duration: AppTheme.Anim.hover), value: isActive)
    }

    private var fill: Color {
        guard isEnabled else { return .clear }
        if isActive, let activeFill { return activeFill }
        return switch (isActive, isHovered) {
        // 纸感浅色：hover/选中靠【压暗】表达，不是提亮。
        case (true, true): AppTheme.Text.primaryColor.opacity(AppTheme.Opacity.soft)
        case (true, false): AppTheme.Text.primaryColor.opacity(AppTheme.Opacity.hint)
        case (false, true): AppTheme.Text.primaryColor.opacity(AppTheme.Opacity.subtle)
        case (false, false): .clear
        }
    }
}

extension View {
    func hoverHighlight(
        cornerRadius: CGFloat = AppTheme.Radius.sm,
        isActive: Bool = false,
        activeFill: Color? = nil
    ) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, isActive: isActive, activeFill: activeFill))
    }
}
