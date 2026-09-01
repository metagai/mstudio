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
        #expect(body.contains("metagCredits = account.credits"),
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
    @Test func theLandingLineNamesWhatHeGot() {
        let hero = Self.source("Home/HomeHero.swift")
        guard let landed = hero.range(of: "case .landed(let credits):") else {
            Issue.record("落地那一步不带余额了")
            return
        }
        let tail = String(hero[landed.lowerBound...].prefix(600))
        #expect(tail.contains("credits.formatted()"),
                "落地只说了'成功'，没说他拿到了什么")
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
    @Test func theLandingLineGoesAway() {
        let src = Self.source("Account/AccountService.swift")
        #expect(src.contains("signInPhase = .idle") && src.contains("Task.sleep(for: .seconds(6))"),
                "落地那句话赖着不走了")
    }

    /// 退出登录要把它清干净，别让上一次的庆祝留在下一次的屏幕上。
    @Test func signingOutClearsTheLanding() async {
        let account = AccountService.shared
        await account.signOut()
        #expect(account.signInPhase == .idle)
    }
}
