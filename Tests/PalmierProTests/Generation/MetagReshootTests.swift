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
