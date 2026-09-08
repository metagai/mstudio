import Foundation

/// 判据用的临时目录，**进程退出时自己删掉**。
///
/// 2026-09-07 创始人看到 `/private/var/folders/…` 一直在写，问是不是我们。
/// 是：`swift test`。而查下来它不只是在写，**是在留**：那个 T 目录里躺着
/// 234 个我们跑判据留下的条目（`FCPXMLExporterTests-` 102 个、
/// `XMLExporterTests-` 54 个……），一次不删、跑一轮多一批。
///
/// 量不大（760KB），**但它是我们自己写在 AGENTS.md 里的规矩**：
/// 「Use unique temporary directories and clean them up」。
/// 服务端那侧同一个形状早就修过了（`/tmp` 攒到 2.0G，最早的文件是七月的，
/// 现在判据的 TMPDIR 指向内存盘），**Mac 这侧一直没修**。
///
/// 用 `atexit` 而不是每条判据 `defer`：调用点有 86 处，
/// 改它们等于把一件基础设施的事摊到每个作者头上 —— 那正是"靠每个人记得"
/// 的做法，这个仓两天里已经验证过三次它活不过两周。
enum TestTemp {
    private static let lock = NSLock()
    // 唯一的可变状态，**只在 `lock` 里碰**。
    nonisolated(unsafe) private static var pending: [URL] = []
    nonisolated(unsafe) private static var installed = false

    static func directory(_ name: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        lock.lock()
        pending.append(url)
        if !installed {
            installed = true
            atexit { TestTemp.sweep() }
        }
        lock.unlock()
        return url
    }

    /// 判据自己要能问"我留了几个" —— 否则"清干净了"只能靠人去数文件夹。
    static var pendingCount: Int {
        lock.lock(); defer { lock.unlock() }
        return pending.count
    }

    private static func sweep() {
        lock.lock()
        let all = pending
        pending = []
        lock.unlock()
        for url in all { try? FileManager.default.removeItem(at: url) }
    }
}
