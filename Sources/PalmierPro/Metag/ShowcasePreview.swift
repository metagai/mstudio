import AVKit
import Foundation

/// 首屏那一排"停上去就活了"的播放器们。
///
/// ## 为什么不放在 View 的 `@State` 里
///
/// 第一版把 `AVPlayer`、`Task`、`NotificationCenter` 的观察者三样都塞进
/// `@State`，靠 `onDisappear` 挨个清。**而 SwiftUI 不保证 `onDisappear` 一定到**
/// （窗口关闭、视图被父级整棵换掉、进程退出前的那一刻都可能不到），
/// 到不了就是一串还在解码的播放器和一串挂着的观察者。
///
/// 一个"多半会被清掉"的资源，和一个泄漏的资源，在开发机上长得一模一样 ——
/// 而它在用户那儿的样子是风扇转起来、电池掉得快。
///
/// 交给一个对象持有，清理挂在 `deinit` 上：**由 ARC 保证，不由回调保证。**
/// 顺带它还能被判据直接问 —— 塞在 `@State` 里的话，唯一的问法是"源码里那行还在吗"。
@MainActor
@Observable
final class ShowcasePreview {
    /// 停下来看，还是路过。**180ms 是这两件事的分界。**
    ///
    /// 鼠标横扫过这一排时不该同时起三个播放器 —— 那既费机器，看起来也慌。
    static let settleDelay: Duration = .milliseconds(180)

    private(set) var players: [String: AVPlayer] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var loops: [String: NSObjectProtocol] = [:]

    /// 该不该为这一张起试播。
    ///
    /// **抽成纯函数是因为判据没有鼠标** —— 留在闭包里的话，
    /// 唯一的问法就是"源码里那行还在吗"。
    nonisolated static func shouldPreview(alreadyPlaying: Bool, alreadyPreviewing: Bool) -> Bool {
        // 大播放器开着的时候不抢它：他已经在认真看一条了，
        // 旁边那张跟着动起来是打扰，不是惊喜。
        !alreadyPlaying && !alreadyPreviewing
    }

    func begin(_ film: MetagShowcase, fullPlayerOpen: Bool, stillHovering: @escaping @MainActor () -> Bool) {
        guard Self.shouldPreview(alreadyPlaying: fullPlayerOpen,
                                 alreadyPreviewing: players[film.id] != nil) else { return }
        tasks[film.id]?.cancel()
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, stillHovering(), let self, self.players[film.id] == nil else { return }
            let player = AVPlayer(url: film.reel)
            player.isMuted = true          // 一排同时出声是灾难
            player.actionAtItemEnd = .none
            // 循环：他停在那儿看第二遍是常事，而一条停住的片子看起来像卡住了。
            let token = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
            ) { _ in
                Task { @MainActor in player.seek(to: .zero); player.play() }
            }
            self.loops[film.id] = token
            self.cleanup.tokens.append(token)
            self.players[film.id] = player
            self.cleanup.players.append(player)
            player.play()
        }
        tasks[film.id] = task
        cleanup.tasks.append(task)
    }

    func end(_ id: String) {
        tasks.removeValue(forKey: id)?.cancel()
        players.removeValue(forKey: id)?.pause()
        if let token = loops.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func endAll() {
        for id in Array(players.keys) + Array(tasks.keys) + Array(loops.keys) { end(id) }
    }

    /// **清理由 ARC 保证，不由 `onDisappear` 保证。**
    ///
    /// `deinit` 是 nonisolated 的，碰不到 `@MainActor` 的属性 ——
    /// 所以要清的那三样各自存一份**不带隔离**的镜像。
    ///
    /// 观察者尤其要紧：`NotificationCenter` 那个 token 不摘掉，
    /// 那个闭包会一直活着，而它捕获着一个还在解码的播放器。
    /// 一个"多半会被清掉"的资源和一个泄漏的资源，在开发机上长得一模一样。
    @ObservationIgnored private nonisolated(unsafe) var cleanup = Cleanup()

    /// 只被 `deinit` 读，只在主线程写 —— 两者不会同时发生（对象没了才 deinit）。
    final class Cleanup: @unchecked Sendable {
        var tasks: [Task<Void, Never>] = []
        var players: [AVPlayer] = []
        var tokens: [NSObjectProtocol] = []
    }

    deinit {
        for task in cleanup.tasks { task.cancel() }
        for player in cleanup.players { player.pause() }
        for token in cleanup.tokens { NotificationCenter.default.removeObserver(token) }
    }
}
