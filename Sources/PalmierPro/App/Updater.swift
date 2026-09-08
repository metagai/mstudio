import AppKit
import Sparkle

@MainActor @Observable
final class Updater: NSObject {
    static let shared = Updater()

    private(set) var updateAvailable = false
    private(set) var updateVersion: String?

    private var controller: SPUStandardUpdaterController?
    private var lastBackgroundCheck: Date?
    private var notificationObservers: [NSObjectProtocol] = []

    private override init() {
        super.init()
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        else { return }
        // **只读卷上装不了更新。**
        //
        // 他在磁盘映像里直接用（我们问过一次，他选了"先这样用"），
        // 那 Sparkle 每次检查都会找到新版、下下来、然后写不进去。
        // 结果是一个隔三差五弹出来、每次都失败的更新框 ——
        // 而那件事他做不了什么，真正该做的是把 app 搬进「应用程序」。
        // 不检查，比反复失败强。
        guard !InstallLocation.needsMove(InstallLocation.kind(of: Bundle.main.bundleURL))
        else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        self.controller = controller
        installObservers(updater: controller.updater)
        checkForUpdateInformation()
    }

    /// Sparkle needs a feed *and* an EdDSA public key to install anything. Until METAG has a
    /// signing identity there is neither, so the menu item sends people to the download page
    /// instead of opening a dialog that can only ever fail.
    ///
    /// **中文界面送到备案域。** 这里原来写死 `metag.ai` —— 一个国内用户点"检查更新"，
    /// 被送去一个多半打不开的站，而那一刻他是在主动找我们要新版本。
    /// 两个域都在发同一份落地页（实测各 19 KB / 200），所以这不是二选一，
    /// 是选近的那一个。
    ///
    /// 跟**界面语言**走，不跟服务端 region 走 —— 后者在国内网关重启时会被
    /// nginx 静默兜到海外（合伙人 2026-09-01 实测），而客户端不该继承那个抖动。
    @MainActor
    static var downloadPage: URL {
        AppLocalization.shared.gatewayLanguage == "zh"
            ? URL(string: "https://metag-ai.com/#pillars")!
            : URL(string: "https://metag.ai/#pillars")!
    }

    /// 这一版该去哪儿取更新。**摆成一个函数，判据才问得到** ——
    /// 藏在 delegate 方法里的话，只能靠读源码字符串。
    nonisolated static func feedURL(language: String) -> URL {
        MetagShowcase.siteRoot(language: language).appendingPathComponent("mac/appcast.xml")
    }

    @objc func checkForUpdates(_ sender: Any?) {
        guard let controller else {
            NSWorkspace.shared.open(Self.downloadPage)
            return
        }
        controller.checkForUpdates(sender)
    }

    private func checkForUpdateInformation() {
        lastBackgroundCheck = Date()
        controller?.updater.checkForUpdateInformation()
    }

    private func checkForUpdateIfStale() {
        guard controller != nil else { return }
        let now = Date()
        if let lastBackgroundCheck, now.timeIntervalSince(lastBackgroundCheck) < 3600 { return }
        checkForUpdateInformation()
    }

    private func installObservers(updater: SPUUpdater) {
        let center = NotificationCenter.default

        notificationObservers.append(
            center.addObserver(
                forName: .SUUpdaterDidFindValidUpdate,
                object: updater,
                queue: .main
            ) { [weak self] notification in
                guard let item = notification.userInfo?[SUUpdaterAppcastItemNotificationKey] as? SUAppcastItem else {
                    return
                }
                Task { @MainActor in
                    self?.markUpdateAvailable(item)
                }
            }
        )

        notificationObservers.append(
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.checkForUpdateIfStale()
                }
            }
        )
    }

    private func markUpdateAvailable(_ item: SUAppcastItem) {
        updateAvailable = true
        updateVersion = item.displayVersionString
    }

    private func clearUpdateAvailability() {
        updateAvailable = false
        updateVersion = nil
    }

    private func shouldClearAfterNoUpdateFound(_ error: NSError) -> Bool {
        let reasonRaw = (error.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.intValue
            ?? Int(SPUNoUpdateFoundReason.unknown.rawValue)
        switch SPUNoUpdateFoundReason(rawValue: Int32(reasonRaw)) {
        case .onLatestVersion, .onNewerThanLatestVersion:
            return true
        default:
            return false
        }
    }
}

extension Updater: SPUUpdaterDelegate {
    /// **国内用户去国内那份 appcast 取更新。**
    ///
    /// A0j：`Info.plist` 里的 `SUFeedURL` 写死 `metag.ai`，而合伙人 08-16 实测
    /// 国内取 metag.ai 的大文件是 **14 KB/s** —— 76MB 就是 37 分钟量级。
    /// **不是慢一点，是没有人会等完**，也就是说国内已装用户的自动更新等于不存在。
    ///
    /// 而它一直是绿的：那个 xml 才几 KB，跨洋取得到；Sparkle 不报错；
    /// 我们这侧没有任何一处会红。**它是 0.1.18 第一次有人跟着用户那条路走到底
    /// 才被看见的。**
    ///
    /// 慢的从来不是 appcast，是 dmg。所以国内那份 appcast 的 enclosure 指 OSS
    /// （`release.sh` 发版时一起传），而这里只做一件事：**选近的那份 feed**。
    ///
    /// 跟**界面语言**走，不跟服务端 region 走 —— 和 `downloadPage` 同一条规矩，
    /// 理由也一样：后者在国内网关重启时会被 nginx 静默兜到海外
    /// （合伙人 2026-09-01 实测），客户端不该继承那个抖动。
    @objc func feedURLString(for updater: SPUUpdater) -> String? {
        Self.feedURL(language: AppLocalization.shared.gatewayLanguage).absoluteString
    }

    @objc func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        markUpdateAvailable(item)
    }

    @objc func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        guard let error = error as NSError?, shouldClearAfterNoUpdateFound(error) else { return }
        clearUpdateAvailability()
    }
}
