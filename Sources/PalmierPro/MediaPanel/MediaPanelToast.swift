/// A transient banner shown at the bottom of the media panel
struct MediaPanelToast: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case warning, success, progress }

    /// 这条提示后面可以跟一个动作。
    ///
    /// **片子落到时间轴上的那一刻，屏幕上只有一句「已载入 4 镜」，
    /// 然后什么都没有。** 他刚拿到片子，而"把它留下来"这件事
    /// （导出，也就是我们量的那个内容质量指标）在菜单栏第二层里。
    /// 那一刻是他最想留住它的时候，也是我们唯一不用开口就能请他行动的时候。
    ///
    /// 用枚举不用闭包：这个结构体存在 `@Observable` 的状态里，
    /// 要保持 `Equatable`（不然动画对不上）和 `Sendable`。
    enum Action: Equatable, Sendable {
        case export
    }

    var message: String
    var kind: Kind = .warning
    var action: Action?

    init(message: String, kind: Kind = .warning, action: Action? = nil) {
        self.message = message
        self.kind = kind
        self.action = action
    }
}

// String-literal toasts default to `.warning`; construct explicitly for `.success`.
extension MediaPanelToast: ExpressibleByStringInterpolation {
    init(stringLiteral value: String) {
        self.init(message: value)
    }
    init(stringInterpolation: DefaultStringInterpolation) {
        self.init(message: String(stringInterpolation: stringInterpolation))
    }
}
