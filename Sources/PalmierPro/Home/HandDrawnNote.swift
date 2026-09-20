import SwiftUI

/// A drawn arrow and a short note, pointing up at the line above it.
struct HandDrawnNote: View {
    let text: String

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
    }

    /// **一支笔画上去的箭头，不是一道彩虹。**
    ///
    /// 上一版用彩虹渐变，创始人 2026-09-20 的判断是"箭头不明显" —— 渐变把
    /// 一条本来就细的线拆成几段不同亮度，在深色背景上每一段都不够对比。
    /// 黑白单色 + 更粗的笔画，看得见才谈得上手绘感。
    private var arrow: some View {
        Canvas { ctx, size in
            ctx.stroke(
                Self.strokePath(in: size),
                with: .color(ink),
                style: StrokeStyle(lineWidth: AppTheme.BorderWidth.thick,
                                   lineCap: .round, lineJoin: .round)
            )
        }
    }

    /// 和正文同一个墨色：批注是写在纸上的，不是另一个系统发来的提示。
    private var ink: Color { AppTheme.Text.primaryColor }

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
