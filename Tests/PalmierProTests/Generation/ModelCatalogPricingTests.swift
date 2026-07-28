import Testing
@testable import PalmierPro

@Suite("ModelCatalog — pricing mapping")
struct ModelCatalogPricingTests {

    private func engine(
        id: String = "veo",
        name: String = "Flagship Veo",
        nameI18n: [String: String]? = nil,
        spec: String,
        resolution: String? = nil,
        durationS: Int? = nil,
        audio: Bool = true,
        creditsPerShot: Int
    ) -> MetagGateway.Pricing.Engine {
        MetagGateway.Pricing.Engine(
            id: id, name: name, name_i18n: nameI18n, spec: spec,
            resolution: resolution, duration_s: durationS,
            native_audio: audio, credits_per_shot: creditsPerShot
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

    /// Structured fields are authoritative. Deriving billing inputs from the display string
    /// broke silently whenever `spec` was reworded, so `duration_s` must win over it.
    @Test
    @MainActor
    func structuredDurationOverridesSpecText() throws {
        let entry = ModelCatalog.videoEntry(
            from: engine(spec: "wording changed · 99s", resolution: "720P", durationS: 8, creditsPerShot: 27)
        )
        guard case .video(let caps) = entry.uiCapabilities else {
            Issue.record("expected video capabilities")
            return
        }
        #expect(caps.durations == [8])
        #expect(caps.resolutions == ["720p"])
        let model = VideoModelConfig(entry: entry, caps: caps)
        #expect(
            CostEstimator.videoCost(model: model, durationSeconds: 8, resolution: "720p", generateAudio: true) == 27
        )
    }

    @Test(arguments: [("zh", "带音轨"), ("es", "Con audio"), ("en", "With audio")])
    @MainActor
    func displayNameFollowsRequestedLanguage(code: String, expected: String) {
        let e = engine(
            name: "带音轨",
            nameI18n: ["zh": "带音轨", "en": "With audio", "es": "Con audio"],
            spec: "480P · 8s", durationS: 8, creditsPerShot: 27
        )
        #expect(ModelCatalog.videoEntry(from: e, language: code).displayName == expected)
    }

    /// Older responses carry no `name_i18n`; the legacy `name` must still be used.
    @Test
    @MainActor
    func displayNameFallsBackToLegacyName() {
        let e = engine(name: "Legacy", spec: "480P · 8s", durationS: 8, creditsPerShot: 27)
        #expect(ModelCatalog.videoEntry(from: e, language: "es").displayName == "Legacy")
    }

    /// The gateway meters credits, not subscription tier — nothing from pricing is subscriber-only.
    @Test
    @MainActor
    func enginesAreNotPaidOnly() {
        #expect(ModelCatalog.videoEntry(from: engine(spec: "720P · 5s", creditsPerShot: 24)).paidOnly == false)
    }
}
