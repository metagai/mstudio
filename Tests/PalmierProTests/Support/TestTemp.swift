import Foundation

/// 判据用的临时文件，**进程退出时整个删掉**。
///
/// 2026-09-07 创始人看到 `/private/var/folders/…` 一直在写，问是不是我们。
/// 是：`swift test`。而查下来它不只是在写，**是在留**：那个 T 目录里躺着
/// 234 个我们跑判据留下的条目，一次不删、跑一轮多一批。
/// AGENTS.md 里写着「Use unique temporary directories and clean them up」。
///
/// 一个进程一个根目录，判据只管往里放：用 `atexit` 而不是每条判据 `defer`，
/// 因为"靠每个作者记得收拾"在这个仓两天里已经验证过三次活不过两周 ——
/// 而且 `defer` 只删得掉自己建的那个，删不掉被测代码另外生成的（`… 2.xml`）。
///
/// `root` 不抛错，所以不能 `throws` 的辅助函数（`makeRegistry()` 这类）也能用。
/// 根目录名本身每个进程唯一，**放在里面的固定文件名不会跨进程撞车**。
enum TestTemp {
    static let root: URL = {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("metag-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        atexit { try? FileManager.default.removeItem(at: TestTemp.root) }
        return url
    }()

    static func directory(_ name: String) throws -> URL {
        let url = root.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
