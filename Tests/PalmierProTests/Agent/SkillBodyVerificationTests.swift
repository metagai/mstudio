import CryptoKit
import Foundation
import Testing
@testable import PalmierPro

@Suite("SkillStore — mirrored body verification")
struct SkillBodyVerificationTests {
    private let body = Data("---\nname: x\ndescription: y\n---\nbody\n".utf8)

    private var fullDigest: String {
        SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
    }

    @Test func acceptsTruncatedCatalogPrefixAndFullDigest() {
        #expect(SkillStore.bodyMatchesCatalogSha(body, String(fullDigest.prefix(12))))
        #expect(SkillStore.bodyMatchesCatalogSha(body, fullDigest))
    }

    @Test func acceptsUppercasePrefix() {
        #expect(SkillStore.bodyMatchesCatalogSha(body, String(fullDigest.prefix(12)).uppercased()))
    }

    @Test func rejectsTamperedBody() {
        let tampered = body + Data("malicious".utf8)
        #expect(!SkillStore.bodyMatchesCatalogSha(tampered, String(fullDigest.prefix(12))))
    }

    @Test(arguments: ["", "zzzzzzzzzzzz", String(repeating: "a", count: 65)])
    func rejectsUnusableCatalogSha(_ sha: String) {
        #expect(!SkillStore.bodyMatchesCatalogSha(body, sha))
    }
}
