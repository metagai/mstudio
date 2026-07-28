import CoreGraphics
import Foundation

/// One source of truth for caption line width and box placement.
/// Shared by the Captions tab preview, caption generation, and template restyling — a caption
/// restyled to a new font size must land in exactly the box generation would have produced.
enum CaptionLayout {
    static func maxTextWidth(canvasWidth: CGFloat) -> CGFloat {
        canvasWidth * AppTheme.ComponentSize.captionPreviewMaxTextWidthRatio
    }

    /// True when the line renders within the caption box without wrapping.
    static func fits(_ text: String, style: TextStyle, canvas: CGSize) -> Bool {
        let size = TextLayout.naturalSize(
            content: text,
            style: style,
            maxWidth: .greatestFiniteMagnitude,
            canvasHeight: canvas.height
        )
        return size.width <= maxTextWidth(canvasWidth: canvas.width)
    }

    static func transform(for text: String, style: TextStyle, center: CGPoint, canvas: CGSize) -> Transform {
        let natural = TextLayout.naturalSize(
            content: text,
            style: style,
            maxWidth: maxTextWidth(canvasWidth: canvas.width),
            canvasHeight: canvas.height
        )
        return Transform(
            center: (Double(center.x), Double(center.y)),
            width: Double(natural.width) / Double(canvas.width),
            height: Double(natural.height) / Double(canvas.height)
        )
    }
}
