import AppKit

Log.bootstrap()
Telemetry.start()
Analytics.start()
// 带上**他是从哪儿启动的**。在 Mac 上「双击磁盘映像里那个图标就开始用」
// 是最常见的一种"装好了"，而它其实没装 —— 自动更新永远失败、
// 弹出映像之后他就再也找不到 METAG。不带这一格的话，
// 这些人和真正装好的人在报表上一模一样。
Analytics.capture(.appOpened, properties: [
    "install": InstallLocation.kind(of: Bundle.main.bundleURL).rawValue
])
BundledFonts.register()
AccountService.shared.configure()
ModelCatalog.shared.configure()

// Shorten the default tooltip delay from 2s to 0.01s.
UserDefaults.standard.set(10, forKey: "NSInitialToolTipDelay")

let app = NSApplication.shared
AppAppearanceStore.shared.apply()
let delegate = AppDelegate.shared
app.delegate = delegate
app.mainMenu = MainMenuBuilder.buildMenu()
app.run()
