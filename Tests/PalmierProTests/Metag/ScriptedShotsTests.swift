import Foundation
import Testing
@testable import PalmierPro

/// **他剧本里写着几镜，就是几镜。**
///
/// 卡片上已经数出来并印给他看了（`第三幕.md · 3 个镜头`），而在这之前
/// 那个数到此为止 —— 提交时照旧交给 METAG 重新猜一遍。**印一个数给他看，
/// 然后不用它，比不印更糟**：他以为我们读懂了他的稿子。
///
/// 这一条和 `chosenShots = nil` 那个默认不冲突：**没写明才交给 METAG 定**，
/// 写明了就是他定了。
@Suite("剧本里写明的镜数")
struct ScriptedShotsTests {
    private static func script(_ text: String) -> PromptAttachment {
        PromptAttachment(title: "script.md", kind: .script(text))
    }

    @Test func aScriptWithMarkersDecidesTheShotCount() {
        let card = Self.script("SHOT 1. 洗衣房。\nSHOT 2. 街道。\nSHOT 3. 天台。")
        #expect(PromptPaste.scriptedShots(in: [card]) == 3)
    }

    /// 没写明就是 nil —— **不凑一个数**，交给读过提示词的那一方去定。
    @Test(arguments: [
        "她把最后一件衣服叠好。\n午后的光斜进来。\n滚筒还在转。\n窗外有车经过。",
        "牛奶\n鸡蛋\n面包",
        "",
    ])
    func proseNeverInventsAShotCount(text: String) {
        #expect(PromptPaste.scriptedShots(in: [Self.script(text)]) == nil)
    }

    @Test func noAttachmentsMeansNoOpinion() {
        #expect(PromptPaste.scriptedShots(in: []) == nil)
    }

    /// 图片不带镜数 —— 它走 assets，不是稿子。
    @Test func imagesDoNotContributeShots() {
        let img = PromptAttachment(title: "ref.png", kind: .image(URL(fileURLWithPath: "/tmp/ref.png")))
        #expect(PromptPaste.scriptedShots(in: [img]) == nil)
    }

    /// 两份稿子就加起来 —— 他给了两幕，那是两幕的总镜数。
    @Test func twoScriptsAddUp() {
        let a = Self.script("SHOT 1.\nSHOT 2.")
        let b = Self.script("第 1 镜\n第 2 镜\n第 3 镜")
        #expect(PromptPaste.scriptedShots(in: [a, b]) == 5)
    }

    /// 那个数要真的走到提交那一步 —— **算出来不用，等于没算。**
    @Test func theCountActuallyReachesTheDraft() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let hero = try String(
            contentsOf: root.appendingPathComponent("Sources/PalmierPro/Home/HomeHero.swift"),
            encoding: .utf8
        )
        #expect(hero.contains("shots: PromptPaste.scriptedShots(in: attachments)"),
                "首屏又把剧本里那个镜数丢了")

        let sheet = try String(
            contentsOf: root.appendingPathComponent("Sources/PalmierPro/Metag/MetagDraftSheet.swift"),
            encoding: .utf8
        )
        #expect(sheet.contains("model.chosenShots = initialShots"),
                "草案表收到了镜数却没用 —— METAG 会重新猜一遍")
    }
}
