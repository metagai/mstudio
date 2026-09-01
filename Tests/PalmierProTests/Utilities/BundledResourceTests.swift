import Foundation
import Testing
@testable import PalmierPro

/// **中文用户拿不到中文界面。**
///
/// 2026-08-31：系统语言是中文的机器上，app 一屏英文，而设置里的语言下拉框
/// **只有一个 "System Language"** —— 21 份语言包全在仓库里，一份都选不到。
///
/// 真因在资源包的找法上：`swift run` 里 token 就是可执行文件所在目录，
/// 而代码往上找了一级 —— 找过头了，`Bundle(url:)` 返回 nil，悄悄回落到
/// `.main`，而 `.main` 里一个 `.lproj` 都没有。
///
/// **它在 `swift test` 里是对的**（那里 token 是 `.xctest`，资源包确实是兄弟）——
/// 所以任何"跑一遍测试看看"的判据都是绿的。判据必须落在**用户走的那条路**上：
/// 直接喂进 `swift run` 那个形状的路径。
@Suite("资源包找得着")
struct BundledResourceTests {
    private static let bundleName = "PalmierPro_PalmierPro.bundle"

    /// `swift run`：token 和 main 都是 `…/debug` 这个目录，资源包在它**里面**。
    @Test func swiftRunLayoutIsCovered() {
        let debug = URL(fileURLWithPath: "/tmp/x/.build/arm64-apple-macosx/debug")
        let found = BundledResource.candidates(token: debug, main: debug, mainResources: nil)
        #expect(found.contains { $0.path == debug.appendingPathComponent(Self.bundleName).path },
                "swift run 的形状没被覆盖 —— 语言下拉框会只剩 System Language")
    }

    /// `swift test`：token 是 `.xctest`，资源包是它的**兄弟**。
    @Test func swiftTestLayoutIsCovered() {
        let debug = URL(fileURLWithPath: "/tmp/x/.build/arm64-apple-macosx/debug")
        let xctest = debug.appendingPathComponent("PalmierProPackageTests.xctest")
        let found = BundledResource.candidates(token: xctest, main: xctest, mainResources: nil)
        #expect(found.contains { $0.path == debug.appendingPathComponent(Self.bundleName).path })
    }

    /// 打好包的 `.app`：资源在 `Contents/Resources` 下。
    @Test func packagedAppLayoutIsCovered() {
        let app = URL(fileURLWithPath: "/Applications/METAG.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        let found = BundledResource.candidates(token: app, main: app, mainResources: resources)
        #expect(found.contains { $0.path == resources.appendingPathComponent(Self.bundleName).path })
    }

    /// 端到端：现在这个进程真的能看见我们维护的三种语言。
    ///
    /// 上面三条守的是**找法**，这一条守的是**东西真的在**（打包脚本漏掉
    /// `.lproj` 的话，上面三条照样全绿）。
    @Test func theMaintainedLanguagesAreActuallyThere() {
        let available = Set(BundledResource.bundle.localizations.map { Locale(identifier: $0).identifier })
        for language in ["en", "zh-Hans", "es"] {
            #expect(available.contains(language), "语言包里没有 \(language) —— 那门语言的用户只能看英文")
        }
    }

    /// 语言选择器里必须真的能选到中文。**下拉框里只有 System Language
    /// 等于中文用户没有出路。**
    @Test @MainActor func theLanguagePickerOffersChinese() {
        let localization = AppLocalization(resourceBundle: BundledResource.bundle)
        let ids = Set(localization.availableLanguages.compactMap(\.identifier))
        #expect(ids.contains("zh-Hans"), "设置里选不到简体中文")
        #expect(localization.availableLanguages.count > 1, "语言下拉框只剩一个选项")
    }
}
