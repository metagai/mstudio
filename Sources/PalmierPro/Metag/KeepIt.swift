import Foundation

/// **「留下它」要真的把片子留下来，不是打开一个面板。**
///
/// 2026-09-04 的账：漏斗里 `exported` 是 **0** —— 落地 1957 人、
/// 看到自己片子 20 人、**把片子带走 0 人**。那条路的终点还没有人到达过。
///
/// 而首映条上「留下它」按下去，打开的是 759 行的专业导出面板：
/// 目标位置、编码、分辨率、时间线格式、FCPXML 目标、FCPXML 版本、导出队列。
/// **一个刚看完自己第一条片子的人，迎面撞上六个下拉框。**
/// 首映条只有三颗按钮这件事，我曾经拿来当"我们没犯 A00d 那个错"的证据 ——
/// 而那颗按钮通向的正是一个控制面板。
///
/// 所以这里只回答一个问题：**存到哪儿。** 专业面板照旧在标题栏那颗
/// Export 上，想挑参数的人一步就到；不新增按钮，首映条仍是三颗。
enum KeepIt {

    /// 片子存进「影片」文件夹。
    ///
    /// **不弹存储面板。** 面板本身不是墙（它是 Mac 的惯例），但此刻他要的是
    /// "别弄丢它"，不是"决定它叫什么"。存完在访达里点亮，他随时能改名和搬家。
    ///
    /// 重名不覆盖：**覆盖掉的是他上一条片子**，而他多半以为自己在存新的那条。
    nonisolated static func destination(
        name: String,
        ext: String,
        in folder: URL,
        exists: (URL) -> Bool
    ) -> URL {
        let base = sanitized(name)
        var url = folder.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while exists(url) {
            url = folder.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
            // 真出现两千条同名，说明别处坏了；给个尽头，不要活锁。
            if n > 2000 { return folder.appendingPathComponent("\(base) \(UUID().uuidString).\(ext)") }
        }
        return url
    }

    /// 文件名里不能有的字符。**`/` 在 HFS 里会变成 `:`**，而片名来自用户那句话。
    nonisolated static func sanitized(_ name: String) -> String {
        let cleaned = name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t"))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 空名字会生成一个只有扩展名的隐藏文件 —— 他会以为导出失败了。
        // **用已有的 `Untitled`，不新增一句串。** 新增一句就是给 25 个语言
        // 新添一笔欠账（判据会当场红，那是对的），而我读不了其中 23 种 ——
        // 为了一个兜底文件名生成 25 份我验不了的翻译，是拿判据换心安。
        guard !cleaned.isEmpty else { return L10n.string("Untitled") }
        // **255 是字节上限，不是字符上限。** `prefix(200)` 数的是字符 ——
        // 200 个汉字是 600 字节，他那句中文长一点就存不下去。
        // 留出 " 2000.mp4"（约 12 字节）和一点余量。
        return String(decoding: cleaned.utf8.prefix(220), as: UTF8.self)
            // 截在多字节字符中间会留下 U+FFFD，那是个画不出来的方块。
            .replacingOccurrences(of: "\u{FFFD}", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// 真的存下去。
    ///
    /// 复用导出队列那条唯一的路（`enqueueVideo`）—— **不另起一条**，
    /// 否则统计、警告、缺素材提示会有两套各说各话的实现。
    /// 只是把六个下拉框替换成两个不需要他回答的默认值：
    /// H.264（到处都打得开）+ 跟随时间线（**不缩放他的片子** ——
    /// 挑一个分辨率就是替他做了一个他没要的决定）。
    @MainActor
    static func save(_ editor: EditorViewModel) {
        let timeline = editor.timeline
        let url = destination(
            name: timeline.name, ext: ExportFormat.h264.fileExtension,
            in: moviesFolder,
            exists: { FileManager.default.fileExists(atPath: $0.path) }
        )
        do {
            _ = try ExportQueue.shared.enqueueVideo(
                timeline: timeline,
                resolver: editor.mediaResolver,
                resolveTimeline: editor.timelineResolver(),
                format: .h264,
                resolution: .matchTimeline,
                missingMediaRefs: editor.missingMediaRefs,
                outputURL: url,
                source: .keepIt,
                projectID: editor.exportQueueProjectID,
                analyticsProjectID: editor.projectId
            )
        } catch {
            // **失败要出声。** 悄悄失败的「留下它」比一个面板还糟：
            // 他以为片子存好了，关掉应用，然后它不在那儿。
            // 走队列已有的那条失败通知 —— 不另起一处状态，
            // 两处各说各话的错误呈现比没有更糟。
            AppNotifications.exportFailed(
                name: url.lastPathComponent,
                reason: error.localizedDescription
            )
        }
    }

    nonisolated static var moviesFolder: URL {
        FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
    }
}
