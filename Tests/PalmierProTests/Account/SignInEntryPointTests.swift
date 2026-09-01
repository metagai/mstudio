import Foundation
import Testing
@testable import PalmierPro

/// **"Sign in" 不许自己替用户挑一家。**
///
/// 2026-08-31 创始人点开头像里的 "Sign in"，毫无征兆地跳到了 Google 授权页。
/// 那不是那一颗按钮的问题：全 app 有 8 处 `signInWithGoogle()`，四种登录方式
/// 里另外三种只在首页侧栏和引导页出现过。装了这个 app 的人不一定有 Google
/// 账号，国内用户基本上没有 —— 而微信那条链路我们刚接好。
///
/// 判据落在**源码里还有没有写死的那一家**上：单测点不动 `ASWebAuthenticationSession`，
/// 而这条错法的形状就是"某处直接写了 `.google`"。
@Suite("登录入口")
struct SignInEntryPointTests {
    private static let sources: [(path: String, text: String)] = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Account
            .deletingLastPathComponent()   // PalmierProTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // mac
            .appendingPathComponent("Sources/PalmierPro")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        return files.compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return (url.lastPathComponent, text)
        }
    }()

    /// 注释里提这些名字是在讲这段历史，不是调用 —— 判据只看代码行。
    private func expectAbsent(_ needle: String, allowing allowed: Set<String> = [], _ why: String) {
        for file in Self.sources where !allowed.contains(file.path) {
            for (n, line) in file.text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//") else { continue }
                #expect(!code.contains(needle), "\(file.path):\(n + 1) \(why)")
            }
        }
    }

    /// 这个捷径就是那 8 处的来源。它不在了，"顺手跳 Google"就得有人特意写死一家。
    @Test func thereIsNoGoogleShortcut() {
        expectAbsent("signInWithGoogle", "又有了直接跳 Google 的捷径 —— 登录走 SignInMenu")
    }

    /// 除了 `MetagAuth.Provider` 自己的定义，谁都不许在代码里写死一家。
    @Test func noScreenPicksAProviderForTheUser() {
        expectAbsent("signIn(with: .google)", allowing: ["MetagAuth.swift"],
                     "替用户选了 Google —— 登录入口要给四家")
    }

    /// 按钮上的文案也不许写死一家 —— 一颗写着 "Sign in with Google" 的按钮，
    /// 就算菜单里有四家，用户也已经被告知只有一家了。
    @Test func noButtonNamesASingleProvider() {
        expectAbsent("Sign in with Google", "按钮上写死了一家")
        expectAbsent("Opening Google", "按钮上写死了一家")
    }

    /// 菜单里四家都在，顺序跟 `Provider.allCases` 一致（Apple 在最前）。
    @Test @MainActor func theMenuOffersEveryProvider() {
        let menu = Self.sources.first { $0.path == "SignInMenu.swift" }
        #expect(menu != nil, "SignInMenu 不见了 —— 登录入口没有唯一的所有者了")
        #expect(menu?.text.contains("MetagAuth.Provider.ordered()") == true)
        #expect(MetagAuth.Provider.allCases.count == 4)
    }
}

/// 侧栏底部那一块：**一条分隔线，两行同样的字。**
///
/// 原来是两种控件并排 —— 登录是个 `Menu`（系统小箭头、自己的高亮、`mdLg` 左边距），
/// 设置是 `SidebarRowButton`（`smMd` 左边距、我们的高亮）。两行字对不齐、
/// 两种高亮、一个有箭头一个没有。单独看每行都正常，并排看就是
/// "这两行不是一套东西" —— 而它是首页上除了那句问话之外唯一常驻的东西。
@Suite("侧栏底部")
struct SidebarFooterTests {
    private static func source(_ name: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PalmierPro/\(name)")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// 两行共用同一个样子。**各写各的，迟早会漂** —— 上一版就漂了两个像素的左边距。
    @Test func bothRowsShareOneLook() {
        let src = Self.source("Home/HomeView.swift")
        #expect(src.contains("SidebarRowLabel("), "登录那一行又自己画了")
        #expect(src.contains("SidebarRowButton("))
        // 同一处 padding，不是每行各写一遍。
        #expect(!src.contains("AppTheme.Spacing.mdLg)\n                .padding(.bottom, AppTheme.Spacing.xxs)"),
                "登录那一行又有了自己的边距")
    }

    /// 登录入口只有一处。这里原来自己抄了一遍 provider 循环。
    @Test func theSidebarUsesTheOneSignInEntry() {
        let src = Self.source("Home/HomeView.swift")
        #expect(src.contains("SignInMenu {"), "侧栏又自己搭了一个登录菜单")
        #expect(!src.contains("ForEach(MetagAuth.Provider.ordered()"),
                "provider 循环被抄到了第二处 —— 登录入口就不止一个了")
    }

    /// 它们是**出口**，不是内容的延续 —— 上面要有一条线。
    @Test func theFooterIsSeparatedFromTheContent() {
        #expect(Self.source("Home/HomeView.swift").contains("private var footer: some View"))
    }
}
