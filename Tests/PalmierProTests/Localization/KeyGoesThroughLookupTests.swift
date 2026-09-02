import Foundation
import Testing
@testable import PalmierPro

/// **词条表里有，不等于屏幕会去用它。**
///
/// 2026-09-01 把草案面板渲成图看了一眼：同一屏上，标题、按钮、
/// 「草案免费」是英文，而「镜数由 METAG 定」是中文。
///
/// 原因不是查错了本子，是**压根没查**：`L10n.key` 返回的是 key 本身
/// （一个普通 String），而 `Text(String)` 是**逐字**初始化器 ——
/// 编译器不拦，英文用户看不出任何异常。全仓 60 处，
/// 覆盖了 METAG 的整条付费路径：草案、credits、我的作品、导演组、账户。
///
/// 而 l10n 守卫当时报的是「en 覆盖了全部 1142 个 key」—— **全绿**。
/// 它量的是词条表全不全，不是屏幕用不用。**又一把量了旁边那个东西的尺子。**
@Suite("字要真的过一遍词条表")
struct KeyGoesThroughLookupTests {
    /// 先证明这条路本身是通的。
    ///
    /// **没有这一条，下面那条可能是空绿的** —— 如果 `L10n.string` 自己
    /// 就不翻译，那"都走了 L10n.string"什么也不保证。
    @Test @MainActor func theLookupActuallyTranslates() throws {
        // **不看这台机器的系统语言。** 跟着系统走的话，这条在中文机器上
        // 恒绿、在英文 CI 上恒红 —— 两种都不是在测东西。
        let suite = try #require(UserDefaults(suiteName: "l10n-lookup-\(UUID().uuidString)"))
        defer { suite.removePersistentDomain(forName: suite.description) }
        let zh = AppLocalization(defaults: suite, preferredLanguages: ["zh-Hans"])
        #expect(zh.string("Cancel") == "取消",
                "词条表这条路本身不通了 —— 底下那条守卫会变成空绿的")
    }

    /// **网关的失败文案要是人话，不是 key。**
    ///
    /// 这 29 条出现在他最需要看懂的那一刻：没网、超时、被限流、片子没了。
    /// 它们原来全是 `L10n.key` —— 因为 `errorDescription` 是 nonisolated，
    /// 而查表当时要主线程，够不着。**够不着就退回原文**，
    /// 于是中文用户在失败那一刻看到一行英文。
    @Test @MainActor func theGatewayFailureCopyIsInTheUsersLanguage() throws {
        let suite = try #require(UserDefaults(suiteName: "l10n-fail-\(UUID().uuidString)"))
        defer { suite.removePersistentDomain(forName: suite.description) }
        let zh = AppLocalization(defaults: suite, preferredLanguages: ["zh-Hans"])
        // **必须让生产代码在一本非英文的表下真跑一遍。**
        // 第一版只查了"词条表里有没有中文"，于是把 `errorDescription`
        // 原样改回 `L10n.key` 它照样绿 —— 空绿的守卫，同一个下午第二条。
        let (offline, timeout) = AppLocalization.Catalog.withCatalog(zh.catalog) {
            (MetagGateway.Failure.offline(.notConnectedToInternet).errorDescription,
             MetagGateway.Failure.offline(.timedOut).errorDescription)
        }
        #expect(offline == "连不上网络。检查一下连接再试。",
                "没网那一刻他看到的是「\(offline ?? "nil")」—— 没过词条表")
        #expect(timeout != "The network took too long to answer. Try again.",
                "超时那一刻还是英文原文")
    }

    /// **全局那本表不许等着谁来填对。**
    ///
    /// 第一版它的初始值是 `.main` bundle，等 `AppLocalization.shared` 初始化时
    /// 装进来。于是谁都没碰过 shared 的那条路上，查表退回 `.main` ——
    /// 那里一个 `.lproj` 都没有，整屏英文。「我的作品」那一屏当场就是这样渲出来的。
    ///
    /// 一个"要等别人来填对"的全局，早晚会在没人填的那条路上被读到。
    @Test func theGlobalCatalogIsRightBeforeAnyoneTouchesIt() {
        #expect(AppLocalization.Catalog.current.bundle != .main,
                "全局词条表还是 .main —— 那里没有 .lproj，先被读到的那一屏会是英文")
        #expect(AppLocalization.Catalog.current.bundle
                == AppLocalization.Catalog.resolve().bundle)
    }

    /// 界面控件不许直接吃 `L10n.key` 的返回值。
    ///
    /// `L10n.key` 是给**存进模型的标签**用的（取出来时用 `L10n.string(key:)`
    /// 过一遍表）。直接喂给 `Text` / `Button` 就是把英文原文印在屏幕上。
    @Test func noControlTakesARawKey() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Localization
            .deletingLastPathComponent()   // PalmierProTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // 仓库根
            .appendingPathComponent("Sources/PalmierPro")
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        var scanned = 0
        for case let url as URL in files where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            scanned += 1
            for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//") else { continue }
                for control in ["Text(", "Button(", "Label(", "Toggle(", "Picker("]
                where code.contains(control + "L10n.key(\"") {
                    offenders.append("\(url.lastPathComponent):\(n + 1)")
                }
            }
        }
        // **一把什么都没量到的尺子，比没有尺子更糟。** 第一版这条路径少上溯
        // 了一级，扫到 0 个文件、报绿 —— 把那 60 处原样改回去它也不响。
        #expect(scanned > 400, "只扫到 \(scanned) 个文件 —— 路径又错了，这条守卫是空绿的")
        #expect(offenders.isEmpty,
                "这些地方把英文原文直接印在屏幕上了 —— 改成 L10n.string：\(offenders.prefix(8))")
    }
}
