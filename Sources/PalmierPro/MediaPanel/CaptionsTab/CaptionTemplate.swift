import CoreGraphics
import Foundation

/// Caption look presets: font, fill, background, animation, and placement in one pick.
/// Same six looks as METAG Studio; point sizes are scaled to the caption canvas (Studio's 26px baseline is this editor's 48pt).
struct CaptionTemplate: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    /// What footage it suits — no adjectives.
    let tagline: String
    let style: TextStyle
    let animation: TextAnimation
    let centerY: CGFloat

    var center: CGPoint { CGPoint(x: AppTheme.Caption.centerSnapValue, y: centerY) }

    static let all: [CaptionTemplate] = [
        CaptionTemplate(
            id: "clean",
            name: "Clean Talk",
            tagline: "Explainers — text stays out of the way",
            style: style(size: 48, color: "#FFFFFF", background: 0.55),
            animation: TextAnimation(),
            centerY: AppTheme.Caption.defaultCenterY
        ),
        CaptionTemplate(
            id: "variety",
            name: "Bold Outline",
            tagline: "Fast, high-energy short form",
            style: style(size: 66, color: "#FFE24D", outline: 6),
            animation: TextAnimation(preset: .popIn, highlight: rgba("#FF4D6D")),
            centerY: AppTheme.Caption.defaultCenterY
        ),
        CaptionTemplate(
            id: "karaoke",
            name: "Karaoke",
            tagline: "Lyrics and read-along, word by word",
            style: style(size: 59, color: "#FFFFFF", background: 0.4),
            animation: TextAnimation(preset: .highlightBlock, highlight: rgba("#10B981")),
            centerY: AppTheme.Caption.defaultCenterY
        ),
        CaptionTemplate(
            id: "typewriter",
            name: "Typewriter",
            tagline: "Cold opens and suspense",
            style: style(size: 52, color: "#FFFFFF"),
            animation: TextAnimation(preset: .typewriter),
            centerY: AppTheme.Caption.centerSnapValue
        ),
        CaptionTemplate(
            id: "emphasis",
            name: "Emphasis",
            tagline: "Product pitches — one benefit at a time",
            style: style(size: 62, color: "#FFFFFF"),
            animation: TextAnimation(preset: .highlightPop, highlight: rgba("#FF7A1A")),
            centerY: AppTheme.Caption.defaultCenterY
        ),
        CaptionTemplate(
            id: "minimal",
            name: "Minimal",
            tagline: "Brand films — quiet and restrained",
            style: style(size: 40, color: "#FFFFFFEB", weightBold: false),
            animation: TextAnimation(),
            centerY: AppTheme.Caption.defaultCenterY
        ),
    ]

    private static func rgba(_ hex: String) -> TextStyle.RGBA {
        TextStyle.RGBA(hex: hex) ?? TextStyle.RGBA()
    }

    private static func style(
        size: Double,
        color: String,
        background: Double? = nil,
        outline: Double? = nil,
        weightBold: Bool = true
    ) -> TextStyle {
        var s = TextStyle(fontSize: size)
        s.isBold = weightBold
        s.color = rgba(color)
        s.shadow.enabled = false
        if let background {
            s.background = TextStyle.Background(
                enabled: true,
                color: TextStyle.RGBA(r: 0, g: 0, b: 0, a: background),
                paddingX: size / 3,
                paddingY: size / 6,
                cornerRadius: size / 6
            )
        }
        if let outline {
            s.border = TextStyle.Outline(enabled: true, color: TextStyle.RGBA(r: 0, g: 0, b: 0, a: 1), width: outline)
        }
        return s
    }
}
