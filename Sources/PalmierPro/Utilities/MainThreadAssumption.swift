import Foundation

/// `MainActor.assumeIsolated` 猜错的时候**不是抛错，是 `__builtin_trap()`**。
///
/// 进程当场消失，stderr 上一行 Swift 报错都没有；系统日志里只留下一句
/// `BUG IN CLIENT OF LIBDISPATCH: Assertion failed: Block was expected to
/// execute on queue [com.apple.main-thread]`，而那句话不会进任何崩溃报告的
/// 栈里 —— 崩溃报告上每一条线程都是闲着的。
///
/// **在用户那一侧，它长得和"被静默退出"一模一样。** 2026-08-31 创始人扫完
/// 微信码之后连撞四次，报上来的是「无征兆退出」；同一条断言在那天下午还杀过
/// 他两次，一次在导入素材之后，一次在打开工程之后 —— 都跟登录无关。
///
/// 下面两个函数是它的替身。系统框架**什么时候在哪条线程上回调我们，
/// 不该由我们赌**：猜错的时候报一句，然后做对的事，不杀进程。
enum MainThread {
    /// 做一件事。在主线程就当场做；不在就排回主线程做，并留下一条日志。
    @inline(__always)
    static func run(
        _ file: String = #fileID,
        _ line: Int = #line,
        _ body: @escaping @MainActor () -> Void
    ) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(body)
        } else {
            Log.app.warning("off-main main-actor call at \(file):\(line) — rescheduled")
            Task { @MainActor in body() }
        }
    }

    /// 取一个值。不在主线程就**没有安全的答案** —— 返回 nil，不赌。
    ///
    /// 用到它的全是缓存读取（波形、缩略图、语音掩码）。拿到 nil 的含义是
    /// "这一次没有"，下一帧还会再问一次；而赌错的代价是整个 app 消失。
    @inline(__always)
    static func value<T: Sendable>(
        _ file: String = #fileID,
        _ line: Int = #line,
        _ body: @MainActor () -> T?
    ) -> T? {
        guard Thread.isMainThread else {
            Log.app.warning("off-main main-actor read at \(file):\(line) — returned nil")
            return nil
        }
        return MainActor.assumeIsolated(body)
    }
}
