import AppKit
import SwiftUI

/// 界面明暗。
///
/// ## 为什么以前没有
///
/// 不是没做，是**被四处窗口代码写死成 `.aqua`**。当时的注释写得很清楚：
/// 「删掉会跟随系统，系统切深色时 .ultraThinMaterial 和 systemXxx 会翻，
/// 纸感主题就半坏了」——在那个时点这个判断是对的，因为 `DesignTokens`
/// 只生成了亮色一套，跟随系统只会得到"背景翻了、文字没翻"的半成品。
///
/// 现在 `DesignTokens` 的每个 token 都是动态色（一个 NSColor 自己按外观解析），
/// 所以那个理由不成立了。复查了余下的系统色用法：绝大多数 `Color.black`
/// 是**媒体上的遮罩和信箱边**（两种外观下都该是黑的），真正跟随外观的只有
/// 两处 `.ultraThinMaterial`，而材质本来就该跟随。
///
/// ## 为什么是全局一处而不是逐窗口
///
/// `NSApp.appearance` 会向下级联到所有窗口。逐窗口设置意味着**每新增一个窗口
/// 都要记得设一次**，而漏掉的那个就是暗色下一块刺眼的白 —— 那正是这次要修的病。
/// 所以窗口代码里不再出现 `window.appearance = …`，由这里统一决定。
enum AppearanceMode: String, CaseIterable, Sendable {
    case auto, light, dark

    var label: String {
        switch self {
        case .auto: return L10n.key("Match System")
        case .light: return L10n.key("Light")
        case .dark: return L10n.key("Dark")
        }
    }

    /// nil = 跟随系统。`NSApp.appearance = nil` 就是"不覆盖"。
    var nsAppearance: NSAppearance? {
        switch self {
        case .auto: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum AppearancePreference {
    static let defaultsKey = "appearanceMode"

    /// **默认 auto（跟随系统）**，不是 light。
    /// 用户的系统已经表达过偏好了，开箱就该尊重它；想固定再去设置里改。
    static var mode: AppearanceMode {
        get {
            AppearanceMode(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "")
                ?? .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            // apply() 是主 actor 隔离的（它动 NSApp），而 setter 不是。
            // 显式跳到主 actor，而不是把整个偏好类标成 @MainActor ——
            // 读取偏好本身不需要主线程，那样会让每个读取点都得 await。
            Task { @MainActor in apply() }
        }
    }

    /// 应用到整个 app。启动时调一次，改设置时再调。
    @MainActor
    static func apply() {
        NSApp.appearance = mode.nsAppearance
    }
}
