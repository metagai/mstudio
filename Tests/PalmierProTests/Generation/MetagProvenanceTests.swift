import Testing
import Foundation
@testable import PalmierPro

/// Re-shoot, takes and recipes all need each clip to remember how it was made.
@Suite("METAG 来源信息")
struct MetagProvenanceTests {

    private func roundTrip(_ input: GenerationInput) throws -> GenerationInput {
        let data = try JSONEncoder().encode(input)
        return try JSONDecoder().decode(GenerationInput.self, from: data)
    }

    @Test("四个来源字段存得下、读得回")
    func survivesPersistence() throws {
        var input = GenerationInput(
            prompt: "wide shot of a coffee cup in morning light",
            model: "local",
            duration: 3,
            aspectRatio: "16:9"
        )
        input.backendJobId = "0bd6552a-d4e7-4b23-80e4-773e5d7c6d42"
        input.outputIndex = 2
        let back = try roundTrip(input)
        #expect(back.backendJobId == input.backendJobId)
        #expect(back.outputIndex == 2)
        #expect(back.prompt == input.prompt)
        #expect(back.model == "local")
    }

    @Test("非生成素材没有来源，不该被当成可重拍")
    @MainActor
    func importedAssetHasNoProvenance() {
        let asset = MediaAsset(
            url: URL(fileURLWithPath: "/tmp/my-footage.mov"),
            type: .video,
            name: "my-footage.mov"
        )
        #expect(asset.generationInput == nil)
    }
}
