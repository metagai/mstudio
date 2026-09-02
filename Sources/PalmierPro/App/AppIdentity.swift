enum AppIdentity {
    static let name = "METAG"

    /// 我们在用户硬盘上占的那个文件夹名。
    ///
    /// **它会出现在用户眼前** —— 设置里的「储存空间」一屏把这几条路径原样列出来，
    /// 而在这之前它们写的是 `~/Library/Caches/PalmierPro`：
    /// 一个他从没听说过的名字，出现在他刚装的这个 app 的设置里。
    /// （2026-09-02 创始人指出。）
    ///
    /// 三处落盘位置（缓存、转写、MCP 令牌）以前各写各的字面量 ——
    /// **一处一份名字，加第四处的时候又会漂**。收到这里。
    static let directoryName = name

    /// `~/Library/Caches/METAG`
    static let cachesRoot = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(directoryName, isDirectory: true)

    /// `~/Library/Application Support/METAG`
    static let applicationSupportRoot: URL = {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        )) ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }()
}

import Foundation
