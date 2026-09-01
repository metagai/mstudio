import Foundation
import Testing
@testable import PalmierPro

/// **猜错线程不许杀进程。**
///
/// `MainActor.assumeIsolated` 猜错时是 `__builtin_trap()`：整个 app 当场消失，
/// stderr 上一行 Swift 报错都没有，崩溃报告里每条线程都是闲着的 ——
/// 唯一的痕迹是系统日志里一句 `BUG IN CLIENT OF LIBDISPATCH: Block was
/// expected to execute on queue [com.apple.main-thread]`。
///
/// 2026-08-31 下午它杀了创始人四次：一次在导入素材之后，一次在打开工程之后，
/// 两次在扫完微信码之后。他报上来的是「无征兆退出」—— 因为在他那一侧，
/// 它和"被静默退出"长得一模一样。
///
/// 判据落在**行为**上：真的从别的线程调一次，看它是活着还是死了。
@Suite("主线程假设")
struct MainThreadAssumptionTests {
    /// 从别的线程读一个主线程的值 —— 返回 nil，不崩。
    @Test func readingFromAnotherThreadReturnsNilInsteadOfCrashing() async {
        let value: Int? = await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                #expect(!Thread.isMainThread)
                continuation.resume(returning: MainThread.value { 42 })
            }
        }
        #expect(value == nil, "线程猜错时给了一个答案 —— 那个答案是抢来的")
    }

    /// 在主线程上读，照常给值。
    @Test @MainActor func readingOnTheMainThreadStillWorks() {
        #expect(MainThread.value { 42 } == 42)
    }

    /// 从别的线程做一件事 —— 排回主线程做完，不崩、不丢。
    @Test func workFromAnotherThreadIsRescheduledNotDropped() async {
        let box = await Box()
        await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                MainThread.run { box.done = true; continuation.resume() }
            }
        }
        #expect(await box.done)
    }

    /// 全仓不许再出现裸的 `MainActor.assumeIsolated` —— 系统框架什么时候在
    /// 哪条线程上回调我们，不该由我们赌。
    @Test func noBareAssumeIsolatedRemains() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Utilities
            .deletingLastPathComponent()   // PalmierProTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // mac
            .appendingPathComponent("Sources/PalmierPro")
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        // 唯一允许它出现的地方：MainThread 自己 —— 它先确认了线程再调。
        for url in files where url.lastPathComponent != "MainThreadAssumption.swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), !code.hasPrefix("///") else { continue }
                #expect(!code.contains("MainActor.assumeIsolated"),
                        "\(url.lastPathComponent):\(n + 1) 又在赌线程了 —— 用 MainThread.run / MainThread.value")
            }
        }
    }
}

/// 跨线程写一个标记。`@MainActor` 上的写，读也在 `@MainActor` 上。
@MainActor
private final class Box {
    var done = false
}
