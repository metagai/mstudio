import SwiftUI

/// 边框流光：一条角向渐变绕着圆角边转，用来把视线拉到一处而不占布局。
///
/// Web 端有同名的 `.beam`（conic-gradient + mask），两端要是同一种观感。
/// 这里不能直接旋转描边形状 —— 非正方形转起来会歪；转的是渐变填充本身，
/// 再用描边当遮罩。放大是因为矩形旋转后四角会露白。
private struct BorderBeamModifier: ViewModifier {
    let active: Bool
    let radius: CGFloat
    let color: Color
    let duration: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle: Double = 0

    func body(content: Content) -> some View {
        content.overlay {
            if active, !reduceMotion {
                AngularGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.62),
                        .init(color: color, location: 0.75),
                        .init(color: .clear, location: 0.88),
                        .init(color: .clear, location: 1),
                    ],
                    center: .center
                )
                .scaleEffect(2)
                .rotationEffect(.degrees(angle))
                .mask {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(lineWidth: AppTheme.BorderWidth.thin)
                }
                .allowsHitTesting(false)
                .onAppear {
                    withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                        angle = 360
                    }
                }
            }
        }
    }
}

extension View {
    func borderBeam(
        active: Bool = true,
        radius: CGFloat = AppTheme.Radius.sm,
        // 和 web 端 `.beam` 的 var(--accent) 同源，都来自 design/tokens.json
        color: Color = AppTheme.Accent.brand,
        duration: Double = 6
    ) -> some View {
        modifier(BorderBeamModifier(active: active, radius: radius, color: color, duration: duration))
    }
}
