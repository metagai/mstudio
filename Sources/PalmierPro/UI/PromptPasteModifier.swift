import AppKit
import SwiftUI

/// 在 prompt 输入框上接住 ⌘V。
///
/// **`.onPasteCommand` 在这里不管用。** 输入框聚焦时，粘贴由它内部的
/// `NSTextView` 自己吃掉，SwiftUI 那个修饰符根本收不到 —— 实测：复制一个
/// `.md` 文件按 ⌘V，屏幕上什么都不会发生（2026-08-31）。
///
/// 所以在事件那一层接：聚焦的时候装一个本地按键监视器，我们能收下就收下
/// 并**吃掉这次事件**（否则系统会再粘一遍，卡片和文字同时出现）；
/// 收不下就原样放行，让输入框照常粘它的文字。
private struct PromptPasteMonitor: ViewModifier {
    /// 只在这个框聚焦时才接 —— 本地监视器是全 app 的，不设这一道会去抢别人的粘贴。
    let isFocused: Bool
    /// 收下了返回 true。
    let onPaste: () -> Bool

    /// **监视器闭包只装一次，而 `ViewModifier` 每次刷新都是一个新结构体。**
    /// 直接捕获 `isFocused` 捕到的是装监视器那一刻的值 —— 装的时候还没聚焦，
    /// 它就永远是 false，⌘V 永远原样放行（第一版实测：粘进去的是一串文件路径）。
    /// 所以捕一个引用，值每次刷新写进去。
    @MainActor final class Live {
        var isFocused = false
        var onPaste: () -> Bool = { false }
    }

    @State private var live = Live()
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        live.isFocused = isFocused
        live.onPaste = onPaste
        return content
            .onAppear { install() }
            .onDisappear { remove() }
    }

    private func install() {
        guard monitor == nil else { return }
        let live = live
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers?.lowercased() == "v"
            else { return event }
            // 按键监视器**通常**在主线程上回来，但"通常"不是判据 ——
            // 赌错的代价是整个 app 消失（见 `MainThread`）。不在主线程就原样放行：
            // 少收一次粘贴，好过杀掉进程。
            let consumed = MainThread.value { live.isFocused && live.onPaste() } ?? false
            return consumed ? nil : event
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

extension View {
    /// 复制一个文件（或一大段字）粘进这个输入框 —— 收成卡片，别把它撑成一堵墙。
    func promptPaste(isFocused: Bool, onPaste: @escaping () -> Bool) -> some View {
        modifier(PromptPasteMonitor(isFocused: isFocused, onPaste: onPaste))
    }
}
