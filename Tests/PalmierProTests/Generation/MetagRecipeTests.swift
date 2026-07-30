import Testing
import Foundation
@testable import PalmierPro

/// The recipe is the handoff format between mac, the web editor, and an agent, so the
/// shape has to stay byte-compatible and a malformed file has to fail loudly.
@Suite("METAG 配方")
struct MetagRecipeTests {

    private func decode(_ json: String) throws -> MetagRecipe {
        try MetagRecipeIO.decode(Data(json.utf8))
    }

    @Test("认得网页端导出的配方")
    func decodesWebRecipe() throws {
        let recipe = try decode("""
        {"metag_recipe":1,"title":"城市清晨","lang":"zh",
         "shots":[{"prompt":"wide shot of a cafe at dawn","narration":"晨光漫过窗台","engine":"local","seconds":3.06},
                  {"prompt":"close-up of a ceramic mug","narration":"热气升起","engine":"local","seconds":3.06}]}
        """)
        #expect(recipe.shots.count == 2)
        #expect(recipe.shots[0].prompt.hasPrefix("wide shot"))
        #expect(recipe.title == "城市清晨")
    }

    @Test("版本号不认识就明确失败，不猜着往下走")
    func rejectsUnknownVersion() {
        #expect(throws: MetagRecipeIO.Failure.self) {
            try decode(#"{"metag_recipe":2,"shots":[{"prompt":"a","narration":""}]}"#)
        }
    }

    @Test("空配方、超 8 镜、缺画面提示词都要拒掉", arguments: [
        "{\"metag_recipe\":1,\"shots\":[]}",
        "{\"metag_recipe\":1,\"shots\":[{\"prompt\":\"   \",\"narration\":\"\"}]}",
    ])
    func rejectsMalformed(json: String) {
        #expect(throws: MetagRecipeIO.Failure.self) { try decode(json) }
    }

    @Test("超过 8 镜拒掉")
    func rejectsTooManyShots() {
        let shots = (0..<9).map { "{\"prompt\":\"shot \($0)\",\"narration\":\"\"}" }.joined(separator: ",")
        #expect(throws: MetagRecipeIO.Failure.self) {
            try decode("{\"metag_recipe\":1,\"shots\":[\(shots)]}")
        }
    }

    /// A recipe written here must be readable by the web editor, which keys off these names.
    @Test("导出的字段名与网页端一致")
    func encodesWebCompatibleKeys() throws {
        let recipe = MetagRecipe(
            title: "t",
            lang: "zh",
            shots: [MetagRecipe.Shot(prompt: "p", narration: "n", engine: "local", seconds: 3)]
        )
        let data = try JSONEncoder().encode(recipe)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["metag_recipe"] as? Int == 1)
        let shots = try #require(object["shots"] as? [[String: Any]])
        #expect(shots[0]["prompt"] as? String == "p")
        #expect(shots[0]["narration"] as? String == "n")
        #expect(shots[0]["engine"] as? String == "local")
    }
}
