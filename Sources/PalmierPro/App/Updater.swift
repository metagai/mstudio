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
    @objc func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        markUpdateAvailable(item)
    }

    @objc func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        guard let error = error as NSError?, shouldClearAfterNoUpdateFound(error) else { return }
        clearUpdateAvailability()
    }
}
