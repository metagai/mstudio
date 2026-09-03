import AppKit

/// 他到底把 METAG 装好了没有。
///
/// ## 在 Mac 上最常见的一种"装好了"，其实没装
///
/// 双击 DMG、双击里面那个图标、直接用起来 —— 很多人就是这么"装"软件的。
/// 而那份 app 活在一个**只读卷**上：
///
/// - 他关掉窗口、弹出磁盘映像，就再也找不到 METAG 了
/// - 在那之前，Sparkle 的自动更新**每一次都会失败**（写不进只读卷），而且一声不响
/// - 他从下载目录直接双击的话，系统还会把它挪到一个随机只读目录跑
///   （App Translocation）—— 同样的结局，而路径怪得他自己都找不着
///
/// **而我们连这件事发生过多少次都不知道。** 启动只报了 `landed`，
/// 没说他是从哪儿启动的 —— 于是"首次安装成功率"在报表上是一片空白。
///
/// ## 做法：不是提醒他做错了，是替他做完
///
/// 发现自己不在「应用程序」里，就问一句、然后自己搬过去、启动那一份、退掉这一份。
/// 他看到的是"点一下，装好了"。
enum InstallLocation {
    enum Kind: String {
        case applications   // 装好了
        case diskImage      // 还在磁盘映像里
        case translocated   // 系统挪到随机只读目录跑（从下载目录直接开会这样）
        case elsewhere      // 别处：开发目录、下载目录、外置盘
    }

    /// **纯函数，判据直接问它。**
    ///
    /// 判断顺序有讲究：磁盘映像里也有一个 `Applications` 软链，
    /// 先判卷再判目录，否则从 DMG 里跑的会被当成"装好了"。
    nonisolated static func kind(of bundle: URL) -> Kind {
        let path = bundle.path
        if path.contains("/AppTranslocation/") { return .translocated }
        if path.hasPrefix("/Volumes/") { return .diskImage }
        if path.contains("/Applications/") { return .applications }
        return .elsewhere
    }

    /// 只有这两种要动他。
    ///
    /// **开发目录和下载目录不弹框。** 下载目录里跑严格说也不算装好，
    /// 但那多半是他自己知道在干什么（或者是我们自己在跑构建产物），
    /// 为它弹一个框换来的打扰多过收益。
    nonisolated static func needsMove(_ kind: Kind) -> Bool {
        kind == .diskImage || kind == .translocated
    }

    /// 搬到哪。`/Applications` 写不进去时退回个人的那一份 —— 不问密码。
    ///
    /// 要提权才能装的软件，在这一步会丢掉一半人。
    nonisolated static func destination(
        appName: String, applications: URL, userApplications: URL,
        isWritable: (URL) -> Bool
    ) -> URL {
        let system = applications.appendingPathComponent(appName)
        return isWritable(applications) ? system : userApplications.appendingPathComponent(appName)
    }
}

@MainActor
extension InstallLocation {
    private static let pendingEjectKey = "MetagPendingEject"

    /// 启动时问一句，然后自己搬过去。
    ///
    /// 搬完**启动新那一份、退掉这一份** —— 不是"请你重新打开"。
    /// 让他去做我们能做的事，就是把机器的难处漏到了用户那一侧。
    static func settleIfNeeded() {
        ejectPendingVolume()
        let bundle = Bundle.main.bundleURL
        guard needsMove(kind(of: bundle)) else { return }

        let fm = FileManager.default
        let target = destination(
            appName: bundle.lastPathComponent,
            applications: URL(fileURLWithPath: "/Applications"),
            userApplications: fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
            isWritable: { fm.isWritableFile(atPath: $0.path) }
        )

        // **他已经装过了，只是又从磁盘映像点了一次。** 别再复制一遍，
        // 直接把装好的那份叫到前面来。
        if fm.fileExists(atPath: target.path), sameVersion(at: target) {
            launch(target, thenQuitFrom: bundle)
            return
        }

        let alert = NSAlert()
        alert.messageText = L10n.string("Put METAG in your Applications folder?")
        alert.informativeText = L10n.string(
            "It's running from the disk image right now. Once it's in Applications you can open it from Launchpad, and updates install themselves.")
        alert.addButton(withTitle: L10n.string("Put in Applications"))
        alert.addButton(withTitle: L10n.string("Not now"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            if fm.fileExists(atPath: target.path) {
                _ = try? fm.trashItem(at: target, resultingItemURL: nil)
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            }
            try fm.copyItem(at: bundle, to: target)
        } catch {
            Log.app.error("move to Applications failed: \(Log.detail(error))")
            // **别把失败讲成事故。** 他还能自己拖，这一句就够了。
            let failed = NSAlert()
            failed.messageText = L10n.string("Couldn't move METAG for you.")
            failed.informativeText = L10n.string("Drag METAG into your Applications folder and open it from there.")
            failed.runModal()
            return
        }
        launch(target, thenQuitFrom: bundle)
    }

    private static func sameVersion(at url: URL) -> Bool {
        guard let other = Bundle(url: url) else { return false }
        return other.infoDictionary?["CFBundleVersion"] as? String
            == Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }

    /// 启动装好的那一份，然后退掉自己。
    ///
    /// 弹出磁盘映像交给**新那一份**去做 —— 我们自己还跑在那个卷上，
    /// 这会儿弹不动。
    private static func launch(_ target: URL, thenQuitFrom bundle: URL) {
        if kind(of: bundle) == .diskImage {
            let volume = "/" + bundle.pathComponents.dropFirst().prefix(2).joined(separator: "/")
            UserDefaults.standard.set(volume, forKey: pendingEjectKey)
        }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: target, configuration: config) { _, error in
            Task { @MainActor in
                if let error {
                    Log.app.error("launching the installed copy failed: \(Log.detail(error))")
                    UserDefaults.standard.removeObject(forKey: pendingEjectKey)
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }

    /// 上一份让我们弹的那个卷。**桌面上留着一个安装盘不算装完。**
    private static func ejectPendingVolume() {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: pendingEjectKey) else { return }
        defaults.removeObject(forKey: pendingEjectKey)
        guard path.hasPrefix("/Volumes/") else { return }
        try? NSWorkspace.shared.unmountAndEjectDevice(at: URL(fileURLWithPath: path))
    }
}
