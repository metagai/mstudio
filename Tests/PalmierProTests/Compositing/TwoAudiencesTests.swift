import Foundation
import Testing
@testable import PalmierPro

/// **一个字符串同时服务两个受众时，本地化它就是在破坏其中一个。**
///
/// 2026-09-02 产品技术负责人在 `SubtitleFileParser` 上撞见这个形状：
/// 它的 `errorDescription` **同时是 `add_captions` 那个 MCP 工具的错误串**，
/// 一本地化，契约判据当场红（AGENTS.md：「不许本地化 Agent 或 MCP 契约」）。
///
/// `LUTStoreError` 是同一族：`ToolExecutor+Color` 读它，而界面那条路
/// 干脆 `try?` 把它整个吞掉 —— 他选完 .cube 文件、点开、面板关掉、
/// **画面一点没变、那一栏还是空的、没有任何提示**。
/// 他会以为自己没选中，再点一次，再次什么都没发生。
///
/// 拆两份：`errorDescription` 给机器（稳定、带路径），`userMessage` 给人。
@Suite("同一个失败，两个受众")
struct TwoAudiencesTests {
    /// 给机器那一份**不许本地化** —— 它是契约。
    @Test @MainActor func theMachineFacingStringStaysStable() throws {
        let suite = try #require(UserDefaults(suiteName: "two-aud-\(UUID().uuidString)"))
        defer { suite.removePersistentDomain(forName: suite.description) }
        let zh = AppLocalization(defaults: suite, preferredLanguages: ["zh-Hans"])
        let text = AppLocalization.Catalog.withCatalog(zh.catalog) {
            LUTStoreError.invalid("look.cube").errorDescription ?? ""
        }
        #expect(text == "Not a valid .cube 3D LUT: look.cube",
                "契约串跟着界面语言变了 —— Agent 那侧的判据会跟着一起变")
    }

    /// 给人那一份**必须本地化**，而且不许把内部路径端给他。
    @Test @MainActor func theHumanFacingStringSpeaksHisLanguage() throws {
        let suite = try #require(UserDefaults(suiteName: "two-aud-h-\(UUID().uuidString)"))
        defer { suite.removePersistentDomain(forName: suite.description) }
        let zh = AppLocalization(defaults: suite, preferredLanguages: ["zh-Hans"])
        let text = AppLocalization.Catalog.withCatalog(zh.catalog) {
            LUTStoreError.noFile("/tmp/x.cube").userMessage
        }
        #expect(text != "No file at path: /tmp/x.cube", "给人的那一份还是契约串")
        #expect(!text.contains("/tmp/"), "把内部路径端给了用户")
    }

    /// **两份必须真的不一样。** 一样的话拆分只是个形式。
    @Test func theTwoAudiencesGetDifferentWords() {
        let e = LUTStoreError.invalid("look.cube")
        #expect(e.userMessage != e.errorDescription)
    }
}
