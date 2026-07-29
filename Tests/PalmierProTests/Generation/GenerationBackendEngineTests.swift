import Testing
@testable import PalmierPro

@Suite("GenerationBackend — engine routing")
@MainActor
struct GenerationBackendEngineTests {

    /// Regression: keyword matching used to route grok/veo/veo-pro to "local", so a shot
    /// quoted at the flagship price came back from the cheapest tier.
    @Test(arguments: ["local", "cloud", "grok", "seedance", "veo", "veo-pro"])
    func gatewayEngineIdsRouteToThemselves(id: String) {
        #expect(GenerationBackend.engine(for: id) == id)
    }

    @Test(arguments: ["  veo-pro  ", "VEO-PRO", "Veo-Pro"])
    func idsAreNormalisedNotReinterpreted(raw: String) {
        #expect(GenerationBackend.engine(for: raw) == "veo-pro")
    }

    @Test
    func emptyIdFallsBackToTheCheapestTier() {
        #expect(GenerationBackend.engine(for: "   ") == "local")
    }
}
