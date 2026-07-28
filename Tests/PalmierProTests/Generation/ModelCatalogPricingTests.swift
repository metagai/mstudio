import Testing
@testable import PalmierPro

@Suite("ModelCatalog — pricing mapping")
struct ModelCatalogPricingTests {

    private func engine(
        id: String = "veo",
        name: String = "Flagship Veo",
        spec: String,
        audio: Bool = true,
        creditsPerShot: Int
    ) -> MetagGateway.Pricing.Engine {
        MetagGateway.Pricing.Engine(
            id: id, name: name, spec: spec, native_audio: audio, credits_per_shot: creditsPerShot
        )
    }

    @Test(arguments: [
        ("480P · 16fps · 3s", 1),
        ("1080P · 5s", 37),
        ("480P · 24fps · 8s", 27),
        ("720P · 5s", 24),
        ("720P · 24fps · 8s", 27),
        ("720P · 24fps · 8s（最高画质）", 54),
    ])
    @MainActor
    func quotedCostEqualsFlatPerShotCharge(spec: String, perShot: Int) throws {
        let entry = ModelCatalog.videoEntry(from: engine(spec: spec, creditsPerShot: perShot))
        guard case .video(let caps) = entry.uiCapabilities else {
            Issue.record("expected video capabilities")
            return
        }
        let duration = try #require(caps.durations.first)
        let model = VideoModelConfig(entry: entry, caps: caps)

        // The picker must quote exactly what the gateway charges per shot.
        #expect(
            CostEstimator.videoCost(
                model: model,
                durationSeconds: duration,
                resolution: caps.resolutions?.first,
                generateAudio: true
            ) == perShot
        )
    }

    @Test(arguments: [
        ("480P · 16fps · 3s", "480p", 3),
        ("1080P · 5s", "1080p", 5),
        ("720P · 24fps · 8s（最高画质）", "720p", 8),
    ])
    func parsesResolutionAndDurationFromSpec(spec: String, resolution: String, seconds: Int) {
        let parsed = ModelCatalog.parseSpec(spec)
        #expect(parsed.resolution == resolution)
        #expect(parsed.seconds == seconds)
    }

    /// An unreadable spec must yield no rate at all — a missing estimate is honest, a guessed one is not.
    @Test
    @MainActor
    func unparsableSpecPublishesNoRate() {
        let entry = ModelCatalog.videoEntry(from: engine(spec: "mystery tier", creditsPerShot: 42))
        #expect(entry.creditsPerSecond == nil)
        guard case .video(let caps) = entry.uiCapabilities else {
            Issue.record("expected video capabilities")
            return
        }
        #expect(caps.durations.isEmpty)
        #expect(VideoModelConfig(entry: entry, caps: caps).creditsPerSecond.isEmpty)
    }

    /// The gateway meters credits, not subscription tier — nothing from pricing is subscriber-only.
    @Test
    @MainActor
    func enginesAreNotPaidOnly() {
        #expect(ModelCatalog.videoEntry(from: engine(spec: "720P · 5s", creditsPerShot: 24)).paidOnly == false)
    }
}
