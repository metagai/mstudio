import Testing
import Foundation
@testable import PalmierPro

/// Eligibility decides whether the menu appears at all, so it has to reject anything we
/// cannot actually re-run rather than offering an action that fails on click.
@Suite("METAG 重拍资格")
@MainActor
struct MetagReshootTests {

    private func asset(job: String?, index: Int?, model: String) -> MediaAsset {
        let a = MediaAsset(
            url: URL(fileURLWithPath: "/tmp/shot.mp4"),
            type: .video,
            name: "shot.mp4"
        )
        var input = GenerationInput(prompt: "a coffee cup", model: model, duration: 3, aspectRatio: "16:9")
        input.backendJobId = job
        input.outputIndex = index
        a.generationInput = input
        return a
    }

    @Test("自研引擎生成的镜头可以重拍")
    func localShotIsEligible() {
        let hit = MetagReshoot.eligibleShot(for: asset(job: "j1", index: 2, model: "local"))
        #expect(hit?.job == "j1")
        #expect(hit?.index == 2)
    }

    @Test("付费引擎的镜头不给右键重拍", arguments: ["veo", "veo-pro", "seedance", "grok", "cloud"])
    func paidEnginesAreNotEligible(model: String) {
        #expect(MetagReshoot.eligibleShot(for: asset(job: "j1", index: 0, model: model)) == nil)
    }

    @Test("缺任务 id 或镜号就不能重拍")
    func incompleteProvenanceIsNotEligible() {
        #expect(MetagReshoot.eligibleShot(for: asset(job: nil, index: 0, model: "local")) == nil)
        #expect(MetagReshoot.eligibleShot(for: asset(job: "", index: 0, model: "local")) == nil)
        #expect(MetagReshoot.eligibleShot(for: asset(job: "j1", index: nil, model: "local")) == nil)
    }

    /// Matching on position instead of provenance silently swaps the wrong shot once a clip
    /// has been reordered or deleted, and a wrong swap is worse than no swap.
    @Test("按来源回找素材，不按位置猜")
    func resolvesAssetByProvenanceNotPosition() {
        let editor = EditorViewModel()
        let second = asset(job: "j1", index: 1, model: "local")
        let first = asset(job: "j1", index: 0, model: "local")
        let other = asset(job: "j2", index: 0, model: "local")
        // Deliberately out of order, as a reordered timeline would leave them.
        editor.mediaAssets = [second, first, other]

        #expect(editor.asset(forJob: "j1", shotIndex: 1)?.id == second.id)
        #expect(editor.asset(forJob: "j1", shotIndex: 0)?.id == first.id)
        #expect(editor.asset(forJob: "j2", shotIndex: 0)?.id == other.id)
        #expect(editor.asset(forJob: "j1", shotIndex: 7) == nil)
    }

    @Test("导入的素材没有来源，不该出现重拍入口")
    func importedFootageIsNotEligible() {
        let a = MediaAsset(
            url: URL(fileURLWithPath: "/tmp/my-footage.mov"),
            type: .video,
            name: "my-footage.mov"
        )
        #expect(MetagReshoot.eligibleShot(for: a) == nil)
    }
}
