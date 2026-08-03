// 【生成物 · 请勿手改】
//
// 由 metag 根仓库的 design/tokens.json 生成。
// 改颜色：改 design/tokens.json，然后在 metag 根目录跑
//     node design/build-tokens.mjs
//
// 校验入口在【根仓库】的 preflight.sh（"== 设计 token" 一节）——
// 它跑 build-tokens.mjs --check，一次覆盖 landing / studio / mac 三端生成物。
// 本仓库单独 clone 时跑不了该检查：tokens.json 在根仓库，不在这里。
// 手改这个文件不会有人拦你，但下一次 preflight 会 FAIL。

import AppKit
import SwiftUI

/// design/tokens.json 的 Swift 投影。
///
/// **每个 token 都是动态色**：一个 `NSColor` 自己按当前外观解析明暗。
/// 这么做的关键收益是**调用点一行都不用改** —— AppTheme 里三百多处引用、
/// 上百个视图，全都自动跟随系统外观。若改成两套常量再逐处判断 colorScheme，
/// 那是几百处改动、且每漏一处就是一块在暗色下发白的死角。
///
/// 颜色一律用 sRGB 色彩空间构造 —— `NSColor(red:…)` 走的是 deviceRGB，
/// 在广色域屏上与 web 端同一个 hex 会渲染成不同的颜色。
///
/// 注意：`Color(nsColor:)` 会保留动态性，`Color(red:green:blue:)` 不会。
/// 下面的 `xxxColor` 一律走前者。
enum DesignTokens {
    /// 按外观取值。invariant 的 token 两套同值，这里也照样走动态色 ——
    /// 少一个分支，就少一处「这个到底跟不跟随外观」的疑问。
    private static func dynamic(
        light: NSColor, dark: NSColor
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    // MARK: - surface

    /// `surface-sunk` — 亮 #EFEBE2 ／ 暗 #0A0C10
    static let surfaceSunk = dynamic(
        light: NSColor(srgbRed: 0.937255, green: 0.921569, blue: 0.886275, alpha: 1),
        dark: NSColor(srgbRed: 0.039216, green: 0.047059, blue: 0.062745, alpha: 1)
    )
    static var surfaceSunkColor: Color { Color(nsColor: surfaceSunk) }

    /// `surface-base` — 亮 #FBFAF8 ／ 暗 #0F1319
    static let surfaceBase = dynamic(
        light: NSColor(srgbRed: 0.984314, green: 0.980392, blue: 0.972549, alpha: 1),
        dark: NSColor(srgbRed: 0.058824, green: 0.07451, blue: 0.098039, alpha: 1)
    )
    static var surfaceBaseColor: Color { Color(nsColor: surfaceBase) }

    /// `surface-raised` — 亮 #FFFFFF ／ 暗 #161B22
    static let surfaceRaised = dynamic(
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        dark: NSColor(srgbRed: 0.086275, green: 0.105882, blue: 0.133333, alpha: 1)
    )
    static var surfaceRaisedColor: Color { Color(nsColor: surfaceRaised) }

    /// `surface-panel` — 亮 #F4F1EA ／ 暗 #1C222B
    static let surfacePanel = dynamic(
        light: NSColor(srgbRed: 0.956863, green: 0.945098, blue: 0.917647, alpha: 1),
        dark: NSColor(srgbRed: 0.109804, green: 0.133333, blue: 0.168627, alpha: 1)
    )
    static var surfacePanelColor: Color { Color(nsColor: surfacePanel) }

    /// `surface-inset` — 亮 #EFEBE2 ／ 暗 #2A323D
    static let surfaceInset = dynamic(
        light: NSColor(srgbRed: 0.937255, green: 0.921569, blue: 0.886275, alpha: 1),
        dark: NSColor(srgbRed: 0.164706, green: 0.196078, blue: 0.239216, alpha: 1)
    )
    static var surfaceInsetColor: Color { Color(nsColor: surfaceInset) }

    /// `surface-hover` — 亮 rgba(17, 17, 18, 0.035) ／ 暗 rgba(255,255,255,0.05)
    static let surfaceHover = dynamic(
        light: NSColor(srgbRed: 0.066667, green: 0.066667, blue: 0.070588, alpha: 0.035),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.05)
    )
    static var surfaceHoverColor: Color { Color(nsColor: surfaceHover) }

    /// `surface-selected` — 亮 rgba(17, 17, 18, 0.07) ／ 暗 rgba(255,255,255,0.09)
    static let surfaceSelected = dynamic(
        light: NSColor(srgbRed: 0.066667, green: 0.066667, blue: 0.070588, alpha: 0.07),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.09)
    )
    static var surfaceSelectedColor: Color { Color(nsColor: surfaceSelected) }


    // MARK: - content

    /// `content-primary` — 亮 #111112 ／ 暗 #E6EAF0
    static let contentPrimary = dynamic(
        light: NSColor(srgbRed: 0.066667, green: 0.066667, blue: 0.070588, alpha: 1),
        dark: NSColor(srgbRed: 0.901961, green: 0.917647, blue: 0.941176, alpha: 1)
    )
    static var contentPrimaryColor: Color { Color(nsColor: contentPrimary) }

    /// `content-secondary` — 亮 #55575C ／ 暗 #9BA0A8
    static let contentSecondary = dynamic(
        light: NSColor(srgbRed: 0.333333, green: 0.341176, blue: 0.360784, alpha: 1),
        dark: NSColor(srgbRed: 0.607843, green: 0.627451, blue: 0.658824, alpha: 1)
    )
    static var contentSecondaryColor: Color { Color(nsColor: contentSecondary) }

    /// `content-tertiary` — 亮 #65676E ／ 暗 #8C939D
    static let contentTertiary = dynamic(
        light: NSColor(srgbRed: 0.396078, green: 0.403922, blue: 0.431373, alpha: 1),
        dark: NSColor(srgbRed: 0.54902, green: 0.576471, blue: 0.615686, alpha: 1)
    )
    static var contentTertiaryColor: Color { Color(nsColor: contentTertiary) }

    /// `content-muted` — 亮 #63656C ／ 暗 #8A9199
    static let contentMuted = dynamic(
        light: NSColor(srgbRed: 0.388235, green: 0.396078, blue: 0.423529, alpha: 1),
        dark: NSColor(srgbRed: 0.541176, green: 0.568627, blue: 0.6, alpha: 1)
    )
    static var contentMutedColor: Color { Color(nsColor: contentMuted) }

    /// `content-on-accent` — 亮 #FFFFFF ／ 暗 #04120C
    static let contentOnAccent = dynamic(
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        dark: NSColor(srgbRed: 0.015686, green: 0.070588, blue: 0.047059, alpha: 1)
    )
    static var contentOnAccentColor: Color { Color(nsColor: contentOnAccent) }


    // MARK: - line

    /// `line-subtle` — 亮 rgba(17, 17, 18, 0.08) ／ 暗 rgba(255,255,255,0.08)
    static let lineSubtle = dynamic(
        light: NSColor(srgbRed: 0.066667, green: 0.066667, blue: 0.070588, alpha: 0.08),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.08)
    )
    static var lineSubtleColor: Color { Color(nsColor: lineSubtle) }

    /// `line-default` — 亮 rgba(17, 17, 18, 0.14) ／ 暗 rgba(255,255,255,0.13)
    static let lineDefault = dynamic(
        light: NSColor(srgbRed: 0.066667, green: 0.066667, blue: 0.070588, alpha: 0.14),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.13)
    )
    static var lineDefaultColor: Color { Color(nsColor: lineDefault) }

    /// `line-strong` — 亮 rgba(17, 17, 18, 0.46) ／ 暗 rgba(255,255,255,0.36)
    static let lineStrong = dynamic(
        light: NSColor(srgbRed: 0.066667, green: 0.066667, blue: 0.070588, alpha: 0.46),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.36)
    )
    static var lineStrongColor: Color { Color(nsColor: lineStrong) }


    // MARK: - accent

    /// `accent` — 亮 #0A7350 ／ 暗 #14C98A
    static let accent = dynamic(
        light: NSColor(srgbRed: 0.039216, green: 0.45098, blue: 0.313725, alpha: 1),
        dark: NSColor(srgbRed: 0.078431, green: 0.788235, blue: 0.541176, alpha: 1)
    )
    static var accentColor: Color { Color(nsColor: accent) }

    /// `accent-hover` — 亮 #086342 ／ 暗 #3BE8AC
    static let accentHover = dynamic(
        light: NSColor(srgbRed: 0.031373, green: 0.388235, blue: 0.258824, alpha: 1),
        dark: NSColor(srgbRed: 0.231373, green: 0.909804, blue: 0.67451, alpha: 1)
    )
    static var accentHoverColor: Color { Color(nsColor: accentHover) }

    /// `accent-glow` — 亮 rgba(14, 143, 99, 0.22) ／ 暗 rgba(20, 201, 138, 0.40)
    static let accentGlow = dynamic(
        light: NSColor(srgbRed: 0.054902, green: 0.560784, blue: 0.388235, alpha: 0.22),
        dark: NSColor(srgbRed: 0.078431, green: 0.788235, blue: 0.541176, alpha: 0.4)
    )
    static var accentGlowColor: Color { Color(nsColor: accentGlow) }

    /// `accent-muted` — 亮 rgba(14, 143, 99, 0.08) ／ 暗 rgba(20, 201, 138, 0.16)
    static let accentMuted = dynamic(
        light: NSColor(srgbRed: 0.054902, green: 0.560784, blue: 0.388235, alpha: 0.08),
        dark: NSColor(srgbRed: 0.078431, green: 0.788235, blue: 0.541176, alpha: 0.16)
    )
    static var accentMutedColor: Color { Color(nsColor: accentMuted) }


    // MARK: - status

    /// `status-danger` — 亮 #C0301F ／ 暗 #F0715F
    static let statusDanger = dynamic(
        light: NSColor(srgbRed: 0.752941, green: 0.188235, blue: 0.121569, alpha: 1),
        dark: NSColor(srgbRed: 0.941176, green: 0.443137, blue: 0.372549, alpha: 1)
    )
    static var statusDangerColor: Color { Color(nsColor: statusDanger) }

    /// `status-warning` — 亮 #8A5F00 ／ 暗 #D8C21E
    static let statusWarning = dynamic(
        light: NSColor(srgbRed: 0.541176, green: 0.372549, blue: 0, alpha: 1),
        dark: NSColor(srgbRed: 0.847059, green: 0.760784, blue: 0.117647, alpha: 1)
    )
    static var statusWarningColor: Color { Color(nsColor: statusWarning) }

    /// `status-success` — 亮 #0A7350 ／ 暗 #14C98A
    static let statusSuccess = dynamic(
        light: NSColor(srgbRed: 0.039216, green: 0.45098, blue: 0.313725, alpha: 1),
        dark: NSColor(srgbRed: 0.078431, green: 0.788235, blue: 0.541176, alpha: 1)
    )
    static var statusSuccessColor: Color { Color(nsColor: statusSuccess) }

    /// `status-info` — 亮 #2C43C7 ／ 暗 #6C7EF5
    static let statusInfo = dynamic(
        light: NSColor(srgbRed: 0.172549, green: 0.262745, blue: 0.780392, alpha: 1),
        dark: NSColor(srgbRed: 0.423529, green: 0.494118, blue: 0.960784, alpha: 1)
    )
    static var statusInfoColor: Color { Color(nsColor: statusInfo) }


    // MARK: - timecode

    /// `timecode-fg` — 亮 #9A5B00 ／ 暗 #F29933
    static let timecodeFg = dynamic(
        light: NSColor(srgbRed: 0.603922, green: 0.356863, blue: 0, alpha: 1),
        dark: NSColor(srgbRed: 0.94902, green: 0.6, blue: 0.2, alpha: 1)
    )
    static var timecodeFgColor: Color { Color(nsColor: timecodeFg) }


    // MARK: - stage

    /// `stage-bg` — 亮 #8C8C8C ／ 暗 #2E2E2E
    static let stageBg = dynamic(
        light: NSColor(srgbRed: 0.54902, green: 0.54902, blue: 0.54902, alpha: 1),
        dark: NSColor(srgbRed: 0.180392, green: 0.180392, blue: 0.180392, alpha: 1)
    )
    static var stageBgColor: Color { Color(nsColor: stageBg) }

    /// `screen-bg` — 亮 #000000 ／ 暗 #000000
    static let screenBg = dynamic(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
        dark: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    )
    static var screenBgColor: Color { Color(nsColor: screenBg) }

    /// `timeline-bg` — 亮 #EFEBE2 ／ 暗 #0A0C10
    static let timelineBg = dynamic(
        light: NSColor(srgbRed: 0.937255, green: 0.921569, blue: 0.886275, alpha: 1),
        dark: NSColor(srgbRed: 0.039216, green: 0.047059, blue: 0.062745, alpha: 1)
    )
    static var timelineBgColor: Color { Color(nsColor: timelineBg) }

    /// `track-bg` — 亮 #F4F1EA ／ 暗 #0F1319
    static let trackBg = dynamic(
        light: NSColor(srgbRed: 0.956863, green: 0.945098, blue: 0.917647, alpha: 1),
        dark: NSColor(srgbRed: 0.058824, green: 0.07451, blue: 0.098039, alpha: 1)
    )
    static var trackBgColor: Color { Color(nsColor: trackBg) }

    /// `waveform` — 亮 rgba(10, 115, 80, 0.80) ／ 暗 rgba(20, 201, 138, 0.85)
    static let waveform = dynamic(
        light: NSColor(srgbRed: 0.039216, green: 0.45098, blue: 0.313725, alpha: 0.8),
        dark: NSColor(srgbRed: 0.078431, green: 0.788235, blue: 0.541176, alpha: 0.85)
    )
    static var waveformColor: Color { Color(nsColor: waveform) }

}
