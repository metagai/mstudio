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

    private static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

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
        /// 面板之间的分界。上游用半透明黑；纸感浅色下那会脏，改走强线令牌。
        static let panel = DesignTokens.lineStrong
        static let timelineClip = DesignTokens.surfaceBase
        /// 选中的片段：缝要反过来吃掉边界，用最高对比的前景色。
        static let timelineClipSelected = DesignTokens.contentPrimary
        /// 标记和片段共用同一套缝色 —— 它们贴在同一条轨上，两套会打架。
        static let timelineMarker = timelineClip
        static let timelineMarkerSelected = timelineClipSelected

        static var primaryColor: Color { Color(primary) }
        static var subtleColor: Color { Color(subtle) }
        static var dividerColor: Color { Color(divider) }
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
        /// 播放头红。NLE 惯例（Premiere / Resolve 同样偏红），浅色下压暗一档才压得住纸。
        static let playheadNSColor = DesignTokens.playheadFg
        static var playheadColor: Color { Color(playheadNSColor) }

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

    /// 一键成片那张草案表的尺寸。**它们此前是视图里的裸数字**
    /// （`frame(width: 460)`、`frame(width: 84, height: 48)`）——
    /// 裸数字没法被一起调，也没法被别的屏复用，那正是"每屏各画各的"的起点。
    enum MetagDraft {
        /// 表的宽度。一行字横跨太宽读不动，这一档是"一段话 + 一排缩略图"的宽度。
        static let sheetWidth: CGFloat = 460
        /// 首帧缩略图。16:9 的一小格，一排能摆下四五个。
        static let frameThumbWidth: CGFloat = 84
        static let frameThumbHeight: CGFloat = 48
        /// 幕布上一格的大小。460 宽的表里一排摆四格（4×96 + 3×6 = 402），
        /// 8 镜自动折成两排。比原来那排邮票大一档 —— **这一刻他想看的是画面，
        /// 不是画面的证明。**
        /// 等待那块幕布上一格多大。
        ///
        /// **原来是 96×54** —— 邮票大小。而那一格里要放的是他这一镜的分镜句
        /// （一句完整的中文），塞进去的结果是三行里每行两三个字、断在"上。"
        /// 这种地方。那九十秒他盯着的东西，读不通。
        ///
        /// 168×94 还是 16:9，一句话能读完，而一行仍放得下三到四格。
        static let stripCellWidth: CGFloat = 168
        static let stripCellHeight: CGFloat = 94
    }

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

        static var pendingColor: Color { Color(NSColor.systemYellow) }
    }

    enum AgentActivity {
        static let added = NSColor.systemGreen
        static let mutated = NSColor.systemOrange
        static let read = NSColor(
            srgbRed: 0x64 / 255.0,
            green: 0x74 / 255.0,
            blue: 0x8B / 255.0,
            alpha: 1
        )
        static let readFill = read.withAlphaComponent(AppTheme.Opacity.faint)
        static let changeGlowOpacity: Float = 0.8
        static let changeGlowRadius: CGFloat = 8
        static let readGlowOpacity: Float = 0.35
        static let readGlowRadius: CGFloat = 4
    }

    enum TimelineMarker {
        static let flagWidth: CGFloat = 10
        static let flagHeight: CGFloat = 12
        static let rangeBarHeight: CGFloat = 4
        static let hitSlop: CGFloat = 3
        static let editorWidth: CGFloat = 320
        static let timeFieldWidth: CGFloat = 82
        static let commentsHeight: CGFloat = 54
        static let presetColors = [
            "#4094FF", "#40CCE6", "#40BF5C", "#F2C72E", "#FF8C26", "#E64040", "#F259A6",
            "#A666F2", "#8CBFFF", "#73E6B8", "#A6D936", "#C79E6B", "#D1D1D1",
        ].compactMap(TextStyle.RGBA.init(hex:))
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

    // MARK: - Interaction fills

    enum Interaction {
        static func fill(_ opacity: Double) -> Color {
            AppTheme.Text.primaryColor.opacity(opacity)
        }
    }

    // MARK: - Media overlays

    enum MediaOverlay {
        static let background = NSColor.black
        static let primary = NSColor.white
        static let secondary = NSColor.white.withAlphaComponent(0.80)
        static let tertiary = NSColor.white.withAlphaComponent(0.62)
        static let muted = NSColor.white.withAlphaComponent(0.34)
        static let error = NSColor(red: 0xE5/255.0, green: 0x4F/255.0, blue: 0x4F/255.0, alpha: 1)

        static var backgroundColor: Color { Color(background) }
        static var primaryColor: Color { Color(primary) }
        static var secondaryColor: Color { Color(secondary) }
        static var tertiaryColor: Color { Color(tertiary) }
        static var mutedColor: Color { Color(muted) }
        static var errorColor: Color { Color(error) }
    }

    // MARK: - Opacity

    enum Opacity {
        static let transparent: Double = 0
        static let opaque: Double = 1
        static let hitTarget: Double = 0.001
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

        /// 按 WCAG 相对亮度在黑白之间选前景 —— 轨道色用户可改，
        /// 写死任何一种前景都会在某个色上读不清。
        static func readableForeground(on background: NSColor) -> NSColor {
            guard let background = background.usingColorSpace(.sRGB) else { return .white }
            let luminance = relativeLuminance(
                red: background.redComponent,
                green: background.greenComponent,
                blue: background.blueComponent
            )
            let blackContrast = (luminance + 0.05) / 0.05
            let whiteContrast = 1.05 / (luminance + 0.05)
            return blackContrast >= whiteContrast ? .black : .white
        }

        private static func relativeLuminance(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGFloat {
            func linear(_ component: CGFloat) -> CGFloat {
                component <= 0.04045
                    ? component / 12.92
                    : pow((component + 0.055) / 1.055, 2.4)
            }
            return linear(red) * 0.2126 + linear(green) * 0.7152 + linear(blue) * 0.0722
        }
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
        /// **4。** `xxs = 2` 并进来了 —— 2pt 和 4pt 摆在一起谁也看不出，
        /// 而两档并存意味着每处都要选一次。2026-09-03 落到 4pt 网格上。
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let smMd: CGFloat = 8
        /// **12。** `md = 10` 并进来了 —— 10 和 12 摆在一起谁也看不出，
        /// 而两档并存意味着每处都要选一次。落到 Apple HIG 的 4pt 网格上。
        static let mdLg: CGFloat = 12
        /// **16。** 原来是 14，和它隔壁的 `lgXl = 16` 差 2pt ——
        /// 肉眼分不出，而选择多了一倍。2026-09-03 两档并成一档，
        /// 落到 Apple HIG 的 4pt 网格上。
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xlXxl: CGFloat = 24
        static let xxl: CGFloat = 28
        /// 首屏留白。比 xxl 大一档，专给"这一屏只有一句问话"的场合。
        static let xxxl: CGFloat = 44
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
        static let captionPreviewMaxTextWidthRatio: CGFloat = 0.9
        static let toolImagePreviewMaxHeight: CGFloat = 50
        static let projectCardWidth: CGFloat = 150
        static let projectCardHeight: CGFloat = 120
        static let projectSearchWidth: CGFloat = 260
        static let timelineClipBorderMinWidth: CGFloat = 8
        static let timelineClipDetailMinWidth: CGFloat = 32
        static let timelineClipControlsMinWidth: CGFloat = 48
        static let timelineTabRenameWidth: CGFloat = 120
        static let timelineTrackHeaderDefaultWidth: CGFloat = 160
        static let timelineTrackHeaderMinimumWidth: CGFloat = 112
        static let timelineTrackHeaderMaximumWidth: CGFloat = 320
        static let timelineTrackHeaderResizeHitWidth: CGFloat = 8
        static let timelineTrackHeaderColorStripWidth: CGFloat = 3
        static let timelineTrackHeaderReorderLeadingInset: CGFloat = 9
        static let timelineKeyframeResizeHandleWidth: CGFloat =
            timelineTrackHeaderReorderLeadingInset + AppTheme.IconSize.md
        static let timelineKeyframeTrackHeaderMinimumWidth: CGFloat = 220
        static let timelineKeyframeValueFieldWidth: CGFloat = 36
        static let timelineKeyframeValueFieldHeight: CGFloat = 18
        static let timelineKeyframeLaneHeight: CGFloat = 24
        static let timelineKeyframeDiamondSize: CGFloat = 8
        static let timelineKeyframeHitSize: CGFloat = 14
        static let timelineClipLabelMinWidth: CGFloat = 56
        static let timelineBadgePadH: CGFloat = 4
        static let timelineBadgePadV: CGFloat = 1
        static let timelineBadgeMinWidth: CGFloat = 16
        static let timelineDotSize: CGFloat = 5
        static let updateOverlayWidth: CGFloat = 640
    }

    /// 「我的作品」那面墙。
    enum FilmWall {
        /// 每张卡最窄这么宽；一行放几张由窗口自己决定。
        static let cardMinWidth: CGFloat = 208
        /// 海报按 16:9 —— 他的片子多数是横的，混排时统一比例才排得齐。
        static let posterAspect: CGFloat = 16.0 / 9
    }

    /// 首屏那几条真片子。
    enum Showcase {
        /// 海报统一这么高，宽度按各自比例走 —— 竖片横片混排，
        /// 等高才排得齐，而一刀切成同宽会把竖片裁掉半张脸。
        static let posterHeight: CGFloat = 116
        /// 展开播放时那块的高度。
        static let playerHeight: CGFloat = 300
    }

    enum Onboarding {
        static let cardWidth: CGFloat = 520
        static let cardHeight: CGFloat = 420
        static let welcomeHeroHeight: CGFloat = 240
        static var secondaryButtonFill: Color {
            AppTheme.Accent.primary.opacity(AppTheme.Opacity.muted)
        }
    }

    enum Settings {
        static let sidebarWidth: CGFloat = 220
        static let contentMaxWidth: CGFloat = 640
        static let creditInputWidth: CGFloat = 56
        static let skillsSearchWidth: CGFloat = 260
        static let skillRowIconFrame: CGFloat = 42
        static let skillStatusWidth: CGFloat = 124
        static let skillActionWidth: CGFloat = 112
        static let skillDetailWidth: CGFloat = 720
        static let skillDetailMinHeight: CGFloat = 600
        static let skillToastWidth: CGFloat = 380
        static let skillMenuWidth: CGFloat = 168
        static let skillToastDuration: Duration = .seconds(5)
    }

    enum EditorPanel {
        static let defaultWidth: CGFloat = 340
        static let minimumWidth: CGFloat = 300
        static let labelColumnWidth: CGFloat = 88
        static let rowMinHeight: CGFloat = 22
        static let groupHeaderHeight: CGFloat = 28
        static let fieldMinHeight: CGFloat = 22
        static let numericFieldWidth: CGFloat = 56
        static let compactNumericFieldWidth: CGFloat = 36
        static let fontMenuWidth: CGFloat = 160
        static let textEditorMinHeight: CGFloat = 96
        static let contentInsets = EdgeInsets(
            top: Spacing.smMd,
            leading: Spacing.smMd + IconSize.xs + Spacing.sm,
            bottom: Spacing.smMd,
            trailing: Spacing.smMd
        )
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
            IconSize.lg * 3 + Spacing.smMd + Spacing.xs + Spacing.sm
        static let projectTitlebarTrailingWidth: CGFloat = 280
        static let settingsDefault = NSSize(width: 1200, height: 800)
        static let settingsMin = NSSize(width: 860, height: 640)
    }

    enum Caption {
        static let defaultFontSize: Double = 48
        static let centerSnapValue: CGFloat = 0.5
        static let centerSnapThreshold: Double = 0.02
        static let defaultCenterY: CGFloat = 0.9
        static let defaultCenter = CGPoint(x: centerSnapValue, y: defaultCenterY)
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
        static let mediaAreaMinHeight: CGFloat = 60
        static let loadingHeight: CGFloat = 180
        static let promptMinHeight: CGFloat = 40
        static let referenceTileWidth: CGFloat = 72
        static let referenceTileHeight: CGFloat = 48
    }

    enum MediaPanel {
        static let contextRowHeight: CGFloat = IconSize.smMd
        static let speakerNameFieldWidth: CGFloat = 96
        static let captionIndexTimecodeWidth: CGFloat = 68
        static let captionIndexDurationWidth: CGFloat = 28
        static let transcriptSourceMenuWidth: CGFloat = 116
        static let markerIndexTimeFieldWidth: CGFloat = 64
        static let markerIndexDurationFieldWidth: CGFloat = 32
        static let markerIndexCommentHeight: CGFloat = 36
        static let markerIndexThumbnailHeight = EditorPanel.fieldMinHeight
            + Spacing.xs + markerIndexCommentHeight
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
        /// 压在画面之上的浮层：底下是用户的素材，阴影只用来分层，不参与造型。
        static let overlay = ShadowStyle(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)
    }

    // MARK: - Animation durations

    enum Anim {
        static let hover: Double = 0.15
        static let transition: Double = 0.2
        static let pulse: Double = 0.8
        static let slipPreviewRefresh: Duration = .milliseconds(67)
        static let agentChangeHighlightHold: Double = 1.0
        static let agentChangeHighlightFade: Double = 0.3
        static let agentChangeHighlightDuration = agentChangeHighlightHold + agentChangeHighlightFade
        static let agentReadHighlightHold: Double = 0.7
        static let agentReadHighlightFade: Double = 0.25
        static let agentReadHighlightDuration = agentReadHighlightHold + agentReadHighlightFade
    }
}

// MARK: - Shadow view modifier

extension View {
    func shadow(_ style: AppTheme.ShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }

    func panelHeaderBar(
        backgroundColor: Color = AppTheme.Background.surfaceColor
    ) -> some View {
        frame(maxWidth: .infinity)
            .frame(height: Layout.panelHeaderHeight)
            .background(backgroundColor)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AppTheme.Border.primaryColor)
                    .frame(height: AppTheme.BorderWidth.thin)
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
        case .subtitle: AppTheme.TrackColor.text
        }
    }

    var themeForegroundColor: NSColor {
        AppTheme.TrackColor.readableForeground(on: themeColor)
    }
}
