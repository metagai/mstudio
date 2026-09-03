import Foundation
import Testing
@testable import PalmierPro

/// **在 Mac 上最常见的一种"装好了"，其实没装。**
///
/// 双击磁盘映像、双击里面那个图标、直接用起来。那份 app 活在只读卷上：
/// 弹出映像他就再也找不到 METAG，而在那之前 Sparkle 的自动更新
/// 每一次都会失败、一声不响。
@Suite("他到底装好了没有")
struct InstallLocationTests {
    @Test(arguments: [
        // 装好了
        ("/Applications/METAG.app", InstallLocation.Kind.applications),
        ("/Users/li/Applications/METAG.app", .applications),
        // 没装好
        ("/Volumes/METAG/METAG.app", .diskImage),
        // 卷名撞车时系统会加个后缀 —— 那也还是磁盘映像
        ("/Volumes/METAG 1/METAG.app", .diskImage),
        ("/private/var/folders/x9/T/AppTranslocation/AB-12/d/METAG.app", .translocated),
        // 别处
        ("/Users/li/Downloads/METAG.app", .elsewhere),
        ("/Users/li/projects/metag/mac/.build/METAG.app", .elsewhere),
    ])
    func itKnowsWhereItIs(path: String, expected: InstallLocation.Kind) {
        #expect(InstallLocation.kind(of: URL(fileURLWithPath: path)) == expected)
    }

    /// **磁盘映像里也有一个 `Applications` 软链。**
    ///
    /// 先判目录再判卷的话，从映像里跑的会被当成"装好了" ——
    /// 而那正是我们要抓的那一种人。
    @Test func theApplicationsAliasInsideTheImageDoesNotCount() {
        let inside = URL(fileURLWithPath: "/Volumes/METAG/Applications/METAG.app")
        #expect(InstallLocation.kind(of: inside) == .diskImage,
                "映像里那个 Applications 软链把'没装好'认成了'装好了'")
    }

    /// 只动那两种。开发目录、下载目录不许弹框打扰。
    @Test func itOnlyInterruptsWhenItHasTo() {
        #expect(InstallLocation.needsMove(.diskImage))
        #expect(InstallLocation.needsMove(.translocated))
        #expect(!InstallLocation.needsMove(.applications))
        #expect(!InstallLocation.needsMove(.elsewhere),
                "在开发目录/下载目录里跑也弹框 —— 每次 swift run 都要点一下")
    }

    /// **不许把一个正在跑的 app 扔进废纸篓。**
    ///
    /// 升级最常见的那条路：已装的那份开着，他又下了新 DMG 双击进来。
    /// 上一版只比版本号 —— 版本不同就覆盖，于是旧进程还在跑，
    /// 而它的 bundle 已经不在原地了。那一份自己会通过自动更新拿到新版。
    @Test func itNeverReplacesACopyThatIsRunning() {
        let installed = URL(fileURLWithPath: "/Applications/METAG.app")
        #expect(InstallLocation.isRunning(at: installed, among: [installed]))
        #expect(InstallLocation.isRunning(at: installed, among: [
            URL(fileURLWithPath: "/Applications/METAG.app/")
        ]), "同一个路径多一个斜杠就认不出来了")
        #expect(!InstallLocation.isRunning(at: installed, among: [
            URL(fileURLWithPath: "/Volumes/METAG/METAG.app")
        ]), "把映像里跑着的这一份当成了装好的那一份 —— 那样永远不会真的装")
        #expect(!InstallLocation.isRunning(at: installed, among: []))
    }

    /// **`/Applications` 写不进去时退回个人那一份，不问密码。**
    ///
    /// 要提权才能装的软件，在这一步会丢掉一半人。
    @Test func itNeverAsksForAPassword() {
        let system = URL(fileURLWithPath: "/Applications")
        let user = URL(fileURLWithPath: "/Users/li/Applications")
        #expect(InstallLocation.destination(
            appName: "METAG.app", applications: system, userApplications: user,
            isWritable: { _ in true }).path == "/Applications/METAG.app")
        #expect(InstallLocation.destination(
            appName: "METAG.app", applications: system, userApplications: user,
            isWritable: { _ in false }).path == "/Users/li/Applications/METAG.app",
            "系统目录写不进去就该退回个人目录，而不是弹一个要密码的框")
    }
}
