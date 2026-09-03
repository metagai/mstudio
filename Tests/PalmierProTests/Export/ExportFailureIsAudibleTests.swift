import Foundation
import Testing
@testable import PalmierPro

/// **导出失败此前是全静默的，而导出是"他愿不愿意留着它"唯一的那一格。**
///
/// 2026-09-02 走查查出：通知那一段被 `guard source == .agent` 挡着 ——
/// **人手点的导出失败不发任何通知**。而标题栏那个唯一的全局指示器
/// 只在 `status.isRunning` 时闪一个点，`.failed` 没有任何呈现；
/// 错误文字只活在 `ExportJob.error` 里，只有重新打开导出面板才看得见。
///
/// 于是：⌘E → 选保存位置 → 关掉面板去干别的 → 十分钟后那个点停了
/// （**和导完一模一样**）→ 去 Finder，没有文件，也不知道为什么。
@Suite("导出失败要出声")
struct ExportFailureIsAudibleTests {
    private func source() throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PalmierPro/Export/ExportQueue.swift"), encoding: .utf8)
    }

    /// 失败的通知**不许再被"谁发起的"挡住**。
    @Test func failureNotifiesNoMatterWhoStartedIt() throws {
        let src = try source()
        guard let gate = src.range(of: "guard let filename, let outputURL else { return }"),
              let failure = src.range(of: "AppNotifications.exportFailed(") else {
            Issue.record("导出结束那一段找不着了")
            return
        }
        #expect(gate.upperBound < failure.lowerBound)
        #expect(!src.contains("guard source == .agent, let filename"),
                "失败通知又被 `source == .agent` 挡住了 —— 人手点的导出失败会全静默")
    }

    /// **那两句话不许是裸英文。** 它们会进系统通知和导出面板。
    @Test @MainActor func theFailureCopyIsInHisLanguage() throws {
        let suite = try #require(UserDefaults(suiteName: "exp-\(UUID().uuidString)"))
        defer { suite.removePersistentDomain(forName: suite.description) }
        let zh = AppLocalization(defaults: suite, preferredLanguages: ["zh-Hans"])
        for english in ["The export finished but produced no file.", "The export didn't finish."] {
            let text = AppLocalization.Catalog.withCatalog(zh.catalog) {
                L10n.string(String.LocalizationValue(english))
            }
            #expect(text != english, "「\(english)」在中文界面里还是英文原文")
        }
    }
}
