import AppKit
import Foundation
import Testing
@testable import PalmierPro

/// **空着的等待是最贵的等待。**
///
/// 2026-08-31 创始人扫完码之后：「过了很久才有响应」。那段时间里屏幕上
/// 什么都不动 —— 他不知道是成了、卡了、还是白扫了。
///
/// 这一组守两件事：等待**短一点**（少打一个来回），以及等待**有话说**
/// （三步各有一句，最后一句说他拿到了什么）。
@Suite("登录的那段等待")
@MainActor
struct SignInWaitTests {
    private static func source(_ name: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PalmierPro/\(name)")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// 登录成功后不许再问一次 `/api/v1/me`。
    ///
    /// 从国内打 `api.metag.ai` 一个来回实测 1.1–1.3 秒。`MetagAuth` 验票时
    /// 已经拿到了那份账号，`AccountService` 回头再拉一次就是白等一个来回 ——
    /// 而这一秒正好落在他最没耐心的那一刻。
    @Test func signingInDoesNotAskTheGatewayTwice() {
        let src = Self.source("Account/AccountService.swift")
        guard let signIn = src.range(of: "func signIn(with provider: MetagAuth.Provider) async {"),
              let signOut = src.range(of: "func signOut() async {") else {
            Issue.record("AccountService 的登录那一段找不着了")
            return
        }
        let body = String(src[signIn.lowerBound..<signOut.lowerBound])
        #expect(!body.contains("refreshMetagAccount()"),
                "登录成功后又去拉了一次账号 —— 同一个接口打两遍，白等一个来回")
        // 断言的是**意图**（用已经验过的那份账号），不是某一行长什么样。
        // 这一行原来写死 `metagCredits = account.credits`，而把解析收敛成
        // 一处 `apply(_:)` 之后它就红了 —— 判据咬住实现细节，
        // 会在代码变好的时候报警。
        #expect(body.contains("apply(account)"),
                "没有用 MetagAuth 已经验过的那份账号")
    }

    /// 三步都要有话说。少一步，那一步就是一段空白的等待。
    @Test func everyPhaseSaysSomething() {
        let hero = Self.source("Home/HomeHero.swift")
        for phase in ["case .waiting", "case .finishing", "case .landed"] {
            #expect(hero.contains(phase), "首屏没说 \(phase) 这一步 —— 那一段又是空白的")
        }
        #expect(hero.contains("ProgressView()"), "等待没有任何在动的东西")
    }

    /// 落地那一句必须**带上余额** —— 他这一趟真正换到的是这个，
    /// 不是一句"登录成功"。
    ///
    /// 这条原来读 `HomeHero.swift` 的源码，断言 `case .landed` 后面有
    /// `credits.formatted()`。2026-09-03 把四档文案收进
    /// `SignInPhase.message`（为了让判据够得着那句话本身）之后，
    /// **它当场红了，而界面一个字没变**。
    /// 判据咬住实现细节，会在代码变好的时候报警。
    @Test func theLandingLineNamesWhatHeGot() {
        let landed = AccountService.SignInPhase.landed(credits: 200).message ?? ""
        #expect(landed.contains("200"),
                "落地只说了'成功'，没说他拿到了什么：\(landed)")
    }

    /// 登录失败要退回原样，不许把"正在登录"留在屏幕上。
    @Test func aFailedSignInClearsThePhase() {
        let src = Self.source("Account/AccountService.swift")
        guard let start = src.range(of: "} catch {\n            signInPhase = .idle") else {
            Issue.record("登录失败没有把状态清掉 —— 屏幕上会一直转")
            return
        }
        #expect(!start.isEmpty)
    }

    /// 落地那句话是一次庆祝，不是常驻横幅 —— 停几秒就走。
    ///
    /// **但那几秒从他看见开始数。** 授权在另一扇窗里完成，他扫完码人还在那一侧；
    /// 等他切回 Mac，六秒早过完了（2026-08-31 创始人：「注意力始终在网页端，
    /// 回到 Mac 端才看到最后那行字」—— 他这次赶上了，慢十秒就赶不上）。
    @Test func theLandingLineWaitsForHimToLook() {
        let src = Self.source("Account/AccountService.swift")
        guard let land = src.range(of: "private func land(credits: Int)") else {
            Issue.record("落地那一段找不着了")
            return
        }
        let body = String(src[land.lowerBound...].prefix(500))
        guard let wait = body.range(of: "waitUntilAppIsFrontmost()"),
              let sleep = body.range(of: "Task.sleep(for: .seconds(6))") else {
            Issue.record("落地那句话要么不走了，要么不等他看见就开始倒计时")
            return
        }
        #expect(wait.lowerBound < sleep.lowerBound,
                "先倒计时再等他回来 —— 那等于没等：他切回来时那句话已经没了")
    }

    /// **没有 app 就没有"前台"可等。**
    ///
    /// `NSApp` 是隐式解包的，单测里它是 nil —— 第一版直接崩在这一行。
    /// 崩在测试里是运气好；同一段代码跑在没有 UI 的地方（命令行导出、
    /// 未来的无头模式）就是崩在用户那里。
    @Test func waitingIsFreeWhenThereIsNoAppToWaitFor() async {
        // **不许挂住。** 第一版没有上限：单测进程里 `NSApp` 存在但永远不会
        // active，于是这个 await 挂死，整套测试从 15 秒变成 20 分钟不结束。
        await waitUntilAppIsFrontmost(timeout: .milliseconds(50))
    }

    /// 退出登录要把它清干净，别让上一次的庆祝留在下一次的屏幕上。
    @Test func signingOutClearsTheLanding() async {
        let account = AccountService.shared
        await account.signOut()
        #expect(account.signInPhase == .idle)
    }
}
