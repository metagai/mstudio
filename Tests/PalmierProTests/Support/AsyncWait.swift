import Foundation

/// 等一个条件成立。**给的是预算，不是保证。**
///
/// ## 为什么抽出来
///
/// 2026-09-03：`VideoProjectLoadTests` 里那条"清单还原会补上缩略图"
/// **五次里红两次**。它自己写了一个 `for _ in 0..<100 { sleep(10ms) }` ——
/// 总共 1 秒，而整套 2000 多条测试并行跑的时候 1 秒不够。
///
/// **门里有一条偶发红，比没有判据更糟：它教会所有人忽略红色。**
/// 而它某天报真事的时候，也会被同一个动作挥手放过。
///
/// 仓库里本来就有一份（`ExportQueueTests.waitUntil`，私有）。
/// 我差点写第三份 —— **先查有没有，再写。**
///
/// ## 为什么还是轮询
///
/// 被等的那件事（`restoreAssetsFromManifest` 的补全）起的是一个
/// **没有句柄的游离 `Task`**，外面没有可以 await 的口子。
/// 真正的修法是给它一个句柄（那样还能在关闭时取消），
/// 但那要动生产代码，不该顺手做在一条测试的修复里。
///
/// 所以这里做两件事：**把预算给足**，以及**在超时那句话里说清楚它是超时**，
/// 不让它长得像"功能坏了"。
enum AsyncWait {
    /// 默认 10 秒 —— 慢机器、并行满载、冷缓存都留了余量。
    @MainActor
    static func until(
        _ description: String,
        timeout: Duration = .seconds(10),
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}
