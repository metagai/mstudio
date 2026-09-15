import SwiftUI

/// A drawn arrow and a short note, pointing up at the line above it.
struct HandDrawnNote: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hue: Double = 0

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.smMd) {
            arrow
                .frame(width: AppTheme.Annotation.arrowLength,
                       height: AppTheme.Annotation.arrowLength)
            Text(text)
                .font(.system(size: AppTheme.FontSize.smMd))
                .italic()
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .allowsHitTesting(false)
        .onAppear(perform: startHueIfAnimating)
    }

    /// Angular gradient masked by the stroke, same approach as `BorderBeam`.
    private var arrow: some View {
        AngularGradient(
            colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red],
            center: .center,
            angle: .degrees(hue)
        )
        .mask {
            Canvas { ctx, size in
                ctx.stroke(
                    Self.strokePath(in: size),
                    with: .color(.white),
                    style: StrokeStyle(lineWidth: AppTheme.BorderWidth.medium,
                                       lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    /// Amber, not the brand green the line above already uses.
    private let ink = AppTheme.Accent.timecodeColor

    private func startHueIfAnimating() {
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: AppTheme.Anim.annotationHue).repeatForever(autoreverses: false)) {
            hue = 360
        }
    }

    /// Curve sweeping up-left, plus a two-line head. Deterministic wobble, so it never reflows.
    static func strokePath(in size: CGSize) -> Path {
        let tip = CGPoint(x: size.width * 0.32, y: 0)
        let tail = CGPoint(x: size.width, y: size.height)
        var path = Path()
        path.move(to: tip)
        let n = AppTheme.Annotation.segments
        for i in 1...n {
            let t = CGFloat(i) / CGFloat(n)
            let base = CGPoint(
                x: tip.x + (tail.x - tip.x) * t,
                y: tip.y + (tail.y - tip.y) * t - size.height * 0.26 * sin(.pi * t)
            )
            path.addLine(to: wobbled(base, t: t, size: size))
        }
        let head = AppTheme.Annotation.arrowHead
        path.move(to: tip)
        path.addLine(to: CGPoint(x: tip.x - head * 0.2, y: tip.y + head))
        path.move(to: tip)
        path.addLine(to: CGPoint(x: tip.x + head, y: tip.y + head * 0.7))
        return path
    }

    /// Fixed-frequency offset perpendicular to the sweep; no randomness, so redraws are identical.
    private static func wobbled(_ p: CGPoint, t: CGFloat, size: CGSize) -> CGPoint {
        let amount = AppTheme.Annotation.jitter * sin(t * 9.4) * (1 - t * 0.5)
        return CGPoint(x: p.x + amount, y: p.y + amount * 0.6)
    }
}
