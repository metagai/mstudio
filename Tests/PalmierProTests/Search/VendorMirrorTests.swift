import Foundation
import Testing
@testable import PalmierPro

@Suite("VendorMirror — source ordering")
struct VendorMirrorTests {
    @Test func mirrorIsPreferredAndUpstreamRetainedAsFallback() {
        let sources = VendorMirror.sources(mirrorPath: "siglip2-base-coreml/v1", upstream: "https://upstream.example/repo")

        #expect(sources.count == 2)
        #expect(sources.first?.absoluteString == "\(VendorMirror.base)/siglip2-base-coreml/v1")
        #expect(sources.last?.absoluteString == "https://upstream.example/repo")
    }

    @Test func identicalMirrorAndUpstreamCollapseToOneSource() {
        let upstream = "\(VendorMirror.base)/dup"
        #expect(VendorMirror.sources(mirrorPath: "dup", upstream: upstream).count == 1)
    }

    @Test func searchModelSourcesPutMirrorAheadOfHuggingFace() {
        let sources = SearchIndexConfig.baseURLs
        #expect(sources.contains(SearchIndexConfig.hostedURL))
        #expect(sources.last == SearchIndexConfig.hostedURL)
    }

    @MainActor
    @Test func skillCatalogSourcesPutMirrorAheadOfGitHub() {
        let bases = SkillCatalog.bases
        #expect(bases.last == SkillCatalog.upstreamBase)
    }
}
