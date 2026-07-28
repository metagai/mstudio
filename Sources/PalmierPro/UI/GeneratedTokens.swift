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
/// 只生成 `light` 一套：这个 app 没有明暗切换机制，多生成一套是死代码。
/// 颜色一律用 sRGB 色彩空间构造 —— `NSColor(red:…)` 走的是 deviceRGB，
/// 在广色域屏上与 web 端同一个 hex 会渲染成不同的颜色。
enum DesignTokens {

    // MARK: - surface

    /// `surface-sunk` = #EFEBE2
    static let surfaceSunk = NSColor(srgbRed: 0.937255, green: 0.921569, blue: 0.886275, alpha: 1)
    static var surfaceSunkColor: Color { Color(surfaceSunk) }

    /// `surface-base` = #FBFAF8
    static let surfaceBase = NSColor(srgbRed: 0.984314, green: 0.980392, blue: 0.972549, alpha: 1)
    static var surfaceBaseColor: Color { Color(surfaceBase) }

    /// `surface-raised` = #FFFFFF
    static let surfaceRaised = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    static var surfaceRaisedColor: Color { Color(surfaceRaised) }

    /// `surface-panel` = #F4F1EA
    static let surfacePanel = NSColor(srgbRed: 0.956863, green: 0.945098, blue: 0.917647, alpha: 1)
    static var surfacePanelColor: Color { Color(surfacePanel) }

    /// `surface-inset` = #EFEBE2
    static let surfaceInset = NSColor(srgbRed: 0.937255, green: 0.921569, blue: 0.886275, alpha: 1)
    static var surfaceInsetColor: Color { Color(surfaceInset) }

    /// `surface-hover` = rgba(17, 17, 18, 0.035)
    static let surfaceHover = NSColor(srgbRed: 0.066667, green: 0.066667, blue: 0.070588, alpha: 0.035)
    static var surfaceHoverColor: Color { Color(surfaceHover) }

    /// `surface-selected` = rgba(17, 17, 18, 0.07)
    static let surfaceSelected = NSColor(srgbRed: 0.066667, green: 0.066667, blue: 0.070588, alpha: 0.07)
    static var surfaceSelectedColor: Color { Color(surfaceSelected) }


    // MARK: - content

    /// `content-primary` = #111112
    static let contentPrimary = NSColor(srgbRed: 0.066667, green: 0.066667, blue: 0.070588, alpha: 1)
    static var contentPrimaryColor: Color { Color(contentPrimary) }

    /// `content-secondary` = #55575C
    static let contentSecondary = NSColor(srgbRed: 0.333333, green: 0.341176, blue: 0.360784, alpha: 1)
    static var contentSecondaryColor: Color { Color(contentSecondary) }

    /// `content-tertiary` = #6F7178
    static let contentTertiary = NSColor(srgbRed: 0.435294, green: 0.443137, blue: 0.470588, alpha: 1)
    static var contentTertiaryColor: Color { Color(contentTertiary) }

    /// `content-muted` = #8A8C92
    static let contentMuted = NSColor(srgbRed: 0.541176, green: 0.54902, blue: 0.572549, alpha: 1)
    static var contentMutedColor: Color { Color(contentMuted) }

    /// `content-on-accent` = #FFFFFF
    static let contentOnAccent = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    static var contentOnAccentColor: Color { Color(contentOnAccent) }


    // MARK: - line

    /// `line-subtle` = rgba(17, 17, 18, 0.08)
    static let lineSubtle = NSColor(srgbRed: 0.066667, green: 0.066667, blue: 0.070588, alpha: 0.08)
    static var lineSubtleColor: Color { Color(lineSubtle) }

    /// `line-default` = rgba(17, 17, 18, 0.14)
    static let lineDefault = NSColor(srgbRed: 0.066667, green: 0.066667, blue: 0.070588, alpha: 0.14)
    static var lineDefaultColor: Color { Color(lineDefault) }

    /// `line-strong` = rgba(17, 17, 18, 0.28)
    static let lineStrong = NSColor(srgbRed: 0.066667, green: 0.066667, blue: 0.070588, alpha: 0.28)
    static var lineStrongColor: Color { Color(lineStrong) }


    // MARK: - accent

    /// `accent` = #0E8F63
    static let accent = NSColor(srgbRed: 0.054902, green: 0.560784, blue: 0.388235, alpha: 1)
    static var accentColor: Color { Color(accent) }

    /// `accent-hover` = #0A7350
    static let accentHover = NSColor(srgbRed: 0.039216, green: 0.45098, blue: 0.313725, alpha: 1)
    static var accentHoverColor: Color { Color(accentHover) }

    /// `accent-glow` = rgba(14, 143, 99, 0.22)
    static let accentGlow = NSColor(srgbRed: 0.054902, green: 0.560784, blue: 0.388235, alpha: 0.22)
    static var accentGlowColor: Color { Color(accentGlow) }

    /// `accent-muted` = rgba(14, 143, 99, 0.08)
    static let accentMuted = NSColor(srgbRed: 0.054902, green: 0.560784, blue: 0.388235, alpha: 0.08)
    static var accentMutedColor: Color { Color(accentMuted) }


    // MARK: - status

    /// `status-danger` = #C93B2A
    static let statusDanger = NSColor(srgbRed: 0.788235, green: 0.231373, blue: 0.164706, alpha: 1)
    static var statusDangerColor: Color { Color(statusDanger) }

    /// `status-warning` = #B8951A
    static let statusWarning = NSColor(srgbRed: 0.721569, green: 0.584314, blue: 0.101961, alpha: 1)
    static var statusWarningColor: Color { Color(statusWarning) }

    /// `status-success` = #0E8F63
    static let statusSuccess = NSColor(srgbRed: 0.054902, green: 0.560784, blue: 0.388235, alpha: 1)
    static var statusSuccessColor: Color { Color(statusSuccess) }

    /// `status-info` = #2C43C7
    static let statusInfo = NSColor(srgbRed: 0.172549, green: 0.262745, blue: 0.780392, alpha: 1)
    static var statusInfoColor: Color { Color(statusInfo) }


    // MARK: - timecode

    /// `timecode-fg` = #F29933
    static let timecodeFg = NSColor(srgbRed: 0.94902, green: 0.6, blue: 0.2, alpha: 1)
    static var timecodeFgColor: Color { Color(timecodeFg) }


    // MARK: - stage

    /// `stage-bg` = #8C8C8C
    static let stageBg = NSColor(srgbRed: 0.54902, green: 0.54902, blue: 0.54902, alpha: 1)
    static var stageBgColor: Color { Color(stageBg) }

    /// `screen-bg` = #000000
    static let screenBg = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    static var screenBgColor: Color { Color(screenBg) }

    /// `timeline-bg` = #EFEBE2
    static let timelineBg = NSColor(srgbRed: 0.937255, green: 0.921569, blue: 0.886275, alpha: 1)
    static var timelineBgColor: Color { Color(timelineBg) }

    /// `track-bg` = #F4F1EA
    static let trackBg = NSColor(srgbRed: 0.956863, green: 0.945098, blue: 0.917647, alpha: 1)
    static var trackBgColor: Color { Color(trackBg) }

    /// `waveform` = rgba(10, 115, 80, 0.80)
    static let waveform = NSColor(srgbRed: 0.039216, green: 0.45098, blue: 0.313725, alpha: 0.8)
    static var waveformColor: Color { Color(waveform) }

}
