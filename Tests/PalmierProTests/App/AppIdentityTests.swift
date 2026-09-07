import Foundation
import Testing
@testable import PalmierPro

/// **系统对话框里那个名字必须是 METAG。**
///
/// 钥匙串弹窗说的是「PalmierPro 想要使用你储存在钥匙串的 "ai.metag" 中的机密信息」——
/// 用户刚装的是 METAG，而**向他要密码的是一个他没听说过的名字**
/// （2026-09-03 创始人截图）。
///
/// 签名身份一直是对的（`ai.metag.mac`），错的是可执行文件的**文件名**：
/// 那个对话框显示的是进程名，而 SwiftPM 的产物名一直沿用着上游的 `PalmierPro`。
/// 打包脚本里甚至写着一句"名字保持 PalmierPro" —— 写下来时它是对的，
/// 而它替这个缺口作了很久的证。
///
/// **这是信任被决定的那一刻**：一个陌生名字向你要钥匙串密码，正确的反应是拒绝。
@Suite("app 的名字")
struct AppIdentityTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // App
        .deletingLastPathComponent()   // PalmierProTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // mac

    /// 三处必须一致：SwiftPM 产物名（= 可执行文件名）、`CFBundleExecutable`、
    /// 打包脚本拷过去的那个名字。**任一处漂了，用户就会看到一个陌生的名字。**
    @Test func theExecutableIsNamedAfterTheApp() throws {
        let manifest = try String(contentsOf: Self.root.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(manifest.contains(".executable(name: \"\(AppIdentity.name)\""),
                "SwiftPM 产物名不是 \(AppIdentity.name) —— 可执行文件会叫别的名字")

        let plist = try String(
            contentsOf: Self.root.appendingPathComponent("Sources/PalmierPro/Resources/Info.plist"),
            encoding: .utf8
        )
        #expect(plist.contains("<string>\(AppIdentity.name)</string>"),
                "CFBundleExecutable 和产物名对不上 —— 打好的 app 起不来")

        let bundleScript = try String(
            contentsOf: Self.root.appendingPathComponent("scripts/bundle.sh"), encoding: .utf8
        )
        #expect(!bundleScript.contains("MacOS/PalmierPro"),
                "打包脚本还在往 MacOS/PalmierPro 拷 —— 上游那个名字又回来了")
    }

    /// **模块名和产物名是两件事，别一起改。**
    ///
    /// 模块名来自 target（仍是 `PalmierPro`），而 `NSDocumentClass` 和资源包
    /// `PalmierPro_PalmierPro.bundle` 都跟着它走。改产物名是安全的，
    /// 改 target 名会同时打断这两处 —— 而打断它们的症状是"打开工程报错"
    /// 和"所有语言包消失"，都不会在编译期报出来。
    @Test func renamingTheProductDoesNotTouchTheModule() throws {
        let plist = try String(
            contentsOf: Self.root.appendingPathComponent("Sources/PalmierPro/Resources/Info.plist"),
            encoding: .utf8
        )
        #expect(plist.contains("PalmierPro.VideoProject"),
                "NSDocumentClass 跟着模块名走 —— 它被改了的话，双击工程文件会打不开")
    }
}
