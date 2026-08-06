import AppKit
import SwiftUI

/// 颜色一律来自 `DesignTokens`（由 metag 根仓库的 design/tokens.json 生成）。
/// 这个文件里不应该再出现任何 `NSColor(red:…)` 字面量 —— 除了明确标注为
/// 「内容语义而非主题」的那几处（亮度滑块的黑→白、示波器的红绿黄）。
///
/// 深色 → 纸感浅色不是机械反相：
///   深色靠「抬亮」分层（base 最暗，越浮起越亮）；
///   浅色靠「压暗 + 细描边」分层，而且白就是天花板 ——
///   所以浮起的东西是白 + 阴影，退后的面板往暗走。两条轴方向不同。
enum AppTheme {

    // MARK: - Backgrounds

    enum Background {
        /// 窗口画布。
        static let base = DesignTokens.surfaceBase
        /// 面板底（侧栏、时间轴区、各种头部）—— 比画布深一档，靠压暗后退。
        static let surface = DesignTokens.surfacePanel
        /// 浮起的东西（卡片、磁贴、菜单、弹层）—— 纯白 + 阴影，靠抬亮前进。
        static let raised = DesignTokens.surfaceRaised
        /// 面板里的凹槽 / 需要强调的小块。
        static let prominent = DesignTokens.surfaceInset

        /// Alias — empty media slot is a raised plate.
        static let placeholder = raised

        static var baseColor: Color { Color(base) }
        static var surfaceColor: Color { Color(surface) }
        static var raisedColor: Color { Color(raised) }
        static var prominentColor: Color { Color(prominent) }
        /// 预览画布恒定纯黑：黑边紧贴画面，白色会把画面冲淡（同时对比）。
        static var previewCanvasColor: Color { DesignTokens.screenBgColor }
        /// 画面【周围】的舞台：中性中灰，既不是白也不是黑。
        /// 中性（R=G=B）是必须的 —— 带彩的包围会偏移对画面色彩的判断。
        static var stageColor: Color { DesignTokens.stageBgColor }
        static var placeholderColor: Color { Color(placeholder) }
        static var clearColor: Color { .clear }
    }

    // MARK: - Borders

    enum Border {
        static let primary = DesignTokens.lineDefault
        static let subtle = DesignTokens.lineSubtle
        static let divider = DesignTokens.lineStrong
        /// 片段之间的缝。片段填充是深色块，缝用纸色才切得开；
        /// 沿用深色时代的纯黑会和片段糊成一片。
        static let timelineClip = DesignTokens.surfaceBase

        static var primaryColor: Color { Color(primary) }
        static var subtleColor: Color { Color(subtle) }
    }

    // MARK: - Border widths

    enum BorderWidth {
        static let hairline: CGFloat = 0.5
        static let thin: CGFloat = 1
        static let medium: CGFloat = 1.5
        static let thick: CGFloat = 2
    }

    // MARK: - Accent

    enum Accent {
        /// 琥珀时间码。这是 NLE 惯例（Premiere / Resolve 同样偏暖），
        /// 与品牌绿是【两个语义角色】，不是同一意图的两个值 —— 所以不收敛成绿色。
        static let timecodeNSColor = DesignTokens.timecodeFg
        static let timecodeColor = Color(timecodeNSColor)

        /// 最高对比度的强调前景/填充（74 处在用）。
        /// 深色时代它是暖白；纸感浅色下同一个角色就是墨色。
        /// 注意：凡是拿它当【填充】的地方，压在上面的文字必须用 `onPrimary`。
        static let primary = DesignTokens.contentPrimaryColor
        /// 压在 `primary` 填充之上的前景。
        static let onPrimary = DesignTokens.surfaceBaseColor

        /// 品牌绿。填充用它时，前景用 `onBrand`。
        static let brand = DesignTokens.accentColor
        static let onBrand = DesignTokens.contentOnAccentColor

        static let link = Color(nsColor: .linkColor)

        /// Vibrant highlight used by the onboarding tour spotlight.
        static let spotlight = Color(red: 1.0, green: 0.27, blue: 0.27)
        static let spotlightGradient = LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.34, blue: 0.30),
                Color(red: 0.95, green: 0.15, blue: 0.28),
                Color(red: 1.0, green: 0.48, blue: 0.22),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    enum Update {
        static let accent = Accent.timecodeColor
    }

    // MARK: - Adjust sliders

    enum Slider {
        static let trackHeight: CGFloat = 4
        static let thumbSize: CGFloat = 10
        static let labelColumn: CGFloat = 106
        /// Temperature track: cool blue (low) → warm amber (high).
        static let tempGradient = [Color(red: 0.32, green: 0.55, blue: 0.92), Color(red: 0.95, green: 0.72, blue: 0.32)]
        /// Tint track: green (low) → magenta (high).
        static let tintGradient = [Color(red: 0.42, green: 0.78, blue: 0.45), Color(red: 0.82, green: 0.38, blue: 0.72)]
        /// Master luma track: near-black → near-white.
        static let lumaGradient = [Color(white: 0.05), Color(white: 0.95)]
    }

    enum AudioMeter {
        static let panelWidth: CGFloat = 32
        static let barWidth: CGFloat = 8
        static let refreshInterval: Double = 1.0 / 30.0
        static let rulerStepDb: Float = 6
        static let rulerMajorStepDb: Float = 12
        static let yellowThresholdDb: Float = -20
        static let redThresholdDb: Float = -6

        static let greenSegment = Color(red: 0.08, green: 0.78, blue: 0.22)
        static let yellowSegment = Color(red: 0.98, green: 0.84, blue: 0.10)
        static let redSegment = Color(red: 0.90, green: 0.24, blue: 0.20)
    }

    // MARK: - Color wheels

    enum Wheels {
        static let padSize: CGFloat = 96
        static let puckSize: CGFloat = 10
        static let ringWidth: CGFloat = 1
        /// 十字线压在彩色色轮上，用墨色才切得出来（原先是白 8%，纸感下等于没有）。
        static let crosshairColor = AppTheme.Text.primaryColor.opacity(AppTheme.Opacity.moderate)
    }

    enum Curve {
        static let editorHeight: CGFloat = 180
        static let pointDiameter: CGFloat = 9
        /// Invisible grab target around each point — much larger than the dot so it's easy to hit.
        static let pointHitDiameter: CGFloat = 30
        /// luma 曲线画在浅色网格上，纯白等于隐形 —— 用墨色。
        /// 下面 RGB 三条是通道指示色，属内容语义，不随主题走。
        static let lumaColor = AppTheme.Text.primaryColor
        static let redColor = Color(red: 1, green: 0.22, blue: 0.18)
        static let greenColor = Color(red: 0.32, green: 0.82, blue: 0.36)
        static let blueColor = Color(red: 0.32, green: 0.56, blue: 1)
    }

    /// AI 微光。深色时代是银白渐变；纸感浅色下必须反过来做成【墨色微光】，
    /// 否则压在纸上完全看不见。亮暗关系反相，但"金属反光"的质感保留。
    static let aiGradient = LinearGradient(
        stops: [
            .init(color: Color(white: 0.10), location: 0.00),
            .init(color: Color(white: 0.34), location: 0.45),
            .init(color: Color(white: 0.52), location: 0.55),
            .init(color: Color(white: 0.10), location: 1.00),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Status

    enum Status {
        static let error = DesignTokens.statusDanger

        static var errorColor: Color { Color(error) }

        static let success = DesignTokens.statusSuccess

        static var successColor: Color { Color(success) }

        /// warning 主要当【小字】用（fps/分辨率不匹配、积分不足、skill 状态）。
        /// systemOrange 在纸底上只有 2.11:1，过不了 AA —— 所以这一个必须收敛。
        /// 跟随系统 appearance 的能力换不来可读性。
        static let warning = DesignTokens.statusWarning

        static var warningColor: Color { Color(warning) }
    }

    // MARK: - Text

    enum Text {
        static let primary = DesignTokens.contentPrimary
        static let secondary = DesignTokens.contentSecondary
        static let tertiary = DesignTokens.contentTertiary
        static let muted = DesignTokens.contentMuted

        static var primaryColor: Color { Color(primary) }
        static var secondaryColor: Color { Color(secondary) }
        static var tertiaryColor: Color { Color(tertiary) }
        static var mutedColor: Color { Color(muted) }

        /// 压在深色块（片段、视频、深色胶囊）之上的文字。
        /// 纸感浅色下 `primary` 是墨色，压在深色片段上会读不出 —— 那种地方用这个。
        static let onDark = DesignTokens.surfaceBase
        static var onDarkColor: Color { Color(onDark) }
    }

    // MARK: - Opacity

    enum Opacity {
        static let opaque: Double = 1
        static let subtle: Double = 0.04
        static let hint: Double = 0.06
        static let faint: Double = 0.08
        static let soft: Double = 0.10
        static let muted: Double = 0.15
        static let moderate: Double = 0.25
        static let medium: Double = 0.35
        static let strong: Double = 0.55
        static let high: Double = 0.70
        static let prominent: Double = 0.80
    }

    // MARK: - Track type colors

    enum TrackColor {
        static let video = NSColor(red: 0x1D/255.0, green: 0x58/255.0, blue: 0x78/255.0, alpha: 1)
        static let audio = NSColor(red: 0x2E/255.0, green: 0x77/255.0, blue: 0x65/255.0, alpha: 1)
        static let image = NSColor(red: 0x71/255.0, green: 0x54/255.0, blue: 0x86/255.0, alpha: 1)
        static let text = NSColor(red: 0x71/255.0, green: 0x54/255.0, blue: 0x86/255.0, alpha: 1)
        static let lottie = NSColor(red: 0xA0/255.0, green: 0x78/255.0, blue: 0x22/255.0, alpha: 1)
        static let sequence = NSColor(red: 0xB9/255.0, green: 0xB2/255.0, blue: 0x9A/255.0, alpha: 1)
        static let multicam = DesignTokens.statusDanger
    }

    // MARK: - Corner radii

    enum Radius {
        static let xs: CGFloat = 3
        static let xsSm: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let mdLg: CGFloat = 12
        static let lg: CGFloat = 14
        static let xl: CGFloat = 20

        static func concentric(outer: CGFloat, padding: CGFloat) -> CGFloat {
            max(outer - padding, 0)
        }
    }

    // MARK: - Spacing

    enum Spacing {
        static let zero: CGFloat = 0
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let smMd: CGFloat = 8
        static let md: CGFloat = 10
        static let mdLg: CGFloat = 12
        static let lg: CGFloat = 14
        static let lgXl: CGFloat = 16
        static let xl: CGFloat = 20
        static let xlXxl: CGFloat = 24
        static let xxl: CGFloat = 28
    }

    // MARK: - Font sizes

    enum FontSize {
        static let micro: CGFloat = 8
        static let xxs: CGFloat = 9
        static let xs: CGFloat = 10
        static let sm: CGFloat = 11
        static let smMd: CGFloat = 12
        static let md: CGFloat = 13
        static let mdLg: CGFloat = 14
        static let lg: CGFloat = 15
        static let xl: CGFloat = 18
        static let title1: CGFloat = 22
        static let title2: CGFloat = 28
        static let display: CGFloat = 36
    }

    // MARK: - Font weights

    enum FontWeight {
        static let light: Font.Weight = .light
        static let regular: Font.Weight = .regular
        static let medium: Font.Weight = .medium
        static let semibold: Font.Weight = .semibold
        static let bold: Font.Weight = .bold
    }

    // MARK: - Tracking (letter-spacing)

    enum Tracking {
        static let tight: CGFloat = -0.5
        static let normal: CGFloat = 0
        static let wide: CGFloat = 1.5
    }

    // MARK: - Icon sizes (square frame dimensions)

    enum IconSize {
        static let xxs: CGFloat = 12
        static let xs: CGFloat = 14
        static let sm: CGFloat = 18
        static let smMd: CGFloat = 20
        static let md: CGFloat = 22
        static let mdLg: CGFloat = 24
        static let lg: CGFloat = 26
        static let lgXl: CGFloat = 28
        static let xl: CGFloat = 30
    }

    enum ComponentSize {
        static let captionPreviewMaxHeight: CGFloat = 150
        static let captionPreviewMaxTextWidthRatio: CGFloat = 0.9
        static let toolImagePreviewMaxHeight: CGFloat = 50
        static let projectCardWidth: CGFloat = 150
        static let projectCardHeight: CGFloat = 120
        static let projectSearchWidth: CGFloat = 260
        static let timelineClipBorderMinWidth: CGFloat = 8
        static let timelineClipDetailMinWidth: CGFloat = 32
        static let timelineClipControlsMinWidth: CGFloat = 48
        static let timelineTabRenameWidth: CGFloat = 120
        static let timelineClipLabelMinWidth: CGFloat = 56
        static let timelineBadgePadH: CGFloat = 4
        static let timelineBadgePadV: CGFloat = 1
        static let timelineBadgeMinWidth: CGFloat = 16
        static let timelineDotSize: CGFloat = 5
        static let updateOverlayWidth: CGFloat = 640
    }

    enum Onboarding {
        static let cardWidth: CGFloat = 520
        static let cardHeight: CGFloat = 420
        static let welcomeHeroHeight: CGFloat = 240
    }

    enum Settings {
        static let sidebarWidth: CGFloat = 220
        static let contentMaxWidth: CGFloat = 640
        static let creditInputWidth: CGFloat = 56
        static let skillsSearchWidth: CGFloat = 260
        static let skillRowIconFrame: CGFloat = 42
        static let skillStatusWidth: CGFloat = 124
        static let skillActionWidth: CGFloat = 72
        static let skillDetailWidth: CGFloat = 720
        static let skillDetailMinHeight: CGFloat = 600
        static let skillToastWidth: CGFloat = 380
        static let skillMenuWidth: CGFloat = 168
        static let skillToastDuration: Duration = .seconds(5)
    }

    enum EditorPanel {
        static let defaultWidth: CGFloat = 340
        static let minimumWidth: CGFloat = 240
        static let labelColumnWidth: CGFloat = 88
        static let rowMinHeight: CGFloat = 22
        static let groupHeaderHeight: CGFloat = 28
        static let tabBarHeight: CGFloat = 34
        static let fieldMinHeight: CGFloat = 22
        static let numericFieldWidth: CGFloat = 56
        static let compactNumericFieldWidth: CGFloat = 36
        static let fontMenuWidth: CGFloat = 160
        static let textEditorMinHeight: CGFloat = 96
    }

    enum Window {
        static let homeDefault = NSSize(width: 1200, height: 800)
        static let homeMin = NSSize(width: 760, height: 480)
        static let projectMin = NSSize(
            width: 960 + GenerationPanel.minimumWidthAdjustment,
            height: 600
        )
        /// 三个面板按钮 + 组间距。窗口标题栏的宿主视图是定宽的，短了会裁掉按钮。
        static let projectTitlebarLeadingWidth: CGFloat =
            IconSize.lg * 3 + Spacing.smMd + Spacing.xxs + Spacing.sm
        static let projectTitlebarTrailingWidth: CGFloat = 280
        static let settingsDefault = NSSize(width: 1200, height: 800)
        static let settingsMin = NSSize(width: 860, height: 640)
    }

    enum Caption {
        static let defaultFontSize: Double = 48
        static let minPosition: Double = 0
        static let maxPosition: Double = 1
        static let centerSnapValue: CGFloat = 0.5
        static let centerSnapThreshold: Double = 0.02
        static let defaultCenterY: CGFloat = 0.9
        static let defaultCenter = CGPoint(x: centerSnapValue, y: defaultCenterY)
        static let minDisplayDuration: Double = 0.7
    }

    enum Director {
        /// Gateway shots are fixed-length; placeholders use it until the real asset lands.
        static let shotDuration = 5
        static let pollInterval: Duration = .seconds(5)
        static let sheetWidth: CGFloat = 520
        static let storyboardMaxHeight: CGFloat = 160
        static let progressBarHeight: CGFloat = 4
    }

    enum GenerationPanel {
        static let typeTabWidth: CGFloat = IconSize.xl + Spacing.lg
        static let minimumWidthAdjustment: CGFloat = typeTabWidth + Spacing.xxl
        static let mediaAreaMinHeight: CGFloat = 120
        static let loadingHeight: CGFloat = 180
        static let promptMinHeight: CGFloat = 40
        static let referenceTileWidth: CGFloat = 80
        static let referenceTileHeight: CGFloat = 56
    }

    enum MediaPanel {
        static let tabRailWidth: CGFloat = IconSize.lg + Spacing.sm * 2
        static let contextRowHeight: CGFloat = IconSize.md
    }

    enum Export {
        static let sheetWidth: CGFloat = 600
        static let sheetHeight: CGFloat = 600
        static let logPaneWidth: CGFloat = 420
        static let queueTimestampWidth: CGFloat = 56
        static let activityDotSize: CGFloat = 6
        static let queueProgressBarWidth: CGFloat = 96
        static let queueProgressWidth: CGFloat = 32
        static let sheetWidthWithLog: CGFloat = sheetWidth + logPaneWidth + BorderWidth.hairline
    }

    enum Matte {
        static let sheetWidth: CGFloat = 280
        static let controlWidth: CGFloat = 116
    }

    // MARK: - Shadows

    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    /// 纸感浅色下阴影必须大幅减轻：深色里 0.3 的黑影是"看不太出来的深"，
    /// 压在纸上会变成一圈脏灰边。浅色靠的是极淡的阴影 + 细描边，不是重投影。
    enum Shadow {
        static let sm = ShadowStyle(color: .black.opacity(0.06), radius: 1, x: 0, y: 0.5)
        static let md = ShadowStyle(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        static let lg = ShadowStyle(color: .black.opacity(0.12), radius: 24, x: 0, y: 8)
    }

    // MARK: - Animation durations

    enum Anim {
        static let hover: Double = 0.15
        static let transition: Double = 0.2
        static let pulse: Double = 0.8
        static let slipPreviewRefresh: Duration = .milliseconds(67)
    }
}

// MARK: - Shadow view modifier

extension View {
    func shadow(_ style: AppTheme.ShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }

    func panelHeaderBar() -> some View {
        frame(maxWidth: .infinity)
            .frame(height: Layout.panelHeaderHeight)
            .background(AppTheme.Background.raisedColor)
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppTheme.Border.primaryColor).frame(height: AppTheme.BorderWidth.thin)
            }
    }
}

// MARK: - ClipType color mapping

extension ClipType {
    var themeColor: NSColor {
        switch self {
        case .video: AppTheme.TrackColor.video
        case .audio: AppTheme.TrackColor.audio
        case .image: AppTheme.TrackColor.image
        case .text: AppTheme.TrackColor.text
        case .lottie: AppTheme.TrackColor.lottie
        case .sequence: AppTheme.TrackColor.sequence
        }
    }
}
