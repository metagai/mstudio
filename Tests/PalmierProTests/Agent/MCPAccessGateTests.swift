import Foundation
import Testing

@testable import PalmierPro

/// The gate has no permissive fallback: anything it cannot positively authenticate is refused.
struct MCPAccessGateTests {

    private let token = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFG"

    private var gate: MCPAccessGate { MCPAccessGate(token: token) }

    @Test func acceptsBearerHeader() {
        #expect(gate.refusal(path: "/mcp", headers: ["Authorization": "Bearer \(token)"], query: nil) == nil)
    }

    @Test func bearerSchemeIsCaseInsensitive() {
        #expect(gate.refusal(path: "/mcp", headers: ["authorization": "bearer \(token)"], query: nil) == nil)
    }

    @Test func acceptsQueryKey() {
        #expect(gate.refusal(path: "/mcp", headers: [:], query: "key=\(token)") == nil)
    }

    @Test(arguments: [
        "", "key=", "key=wrong", "other=\(0)",
    ])
    func refusesBadQuery(_ query: String) {
        #expect(gate.refusal(path: "/mcp", headers: [:], query: query) != nil)
    }

    @Test func refusesMissingCredential() {
        #expect(gate.refusal(path: "/mcp", headers: [:], query: nil) == .missingToken)
    }

    @Test(arguments: [
        "Bearer wrong-token",
        "Bearer ",
        "Basic \("dXNlcjpwYXNz")",
        "\("0123456789abcdefghijklmnopqrstuvwxyzABCDEFG")",
    ])
    func refusesMalformedAuthorization(_ value: String) {
        #expect(gate.refusal(path: "/mcp", headers: ["Authorization": value], query: nil) == .invalidToken)
    }

    /// A near-miss must not slip through on a prefix or length comparison.
    @Test func refusesTruncatedAndExtendedTokens() {
        #expect(gate.refusal(path: "/mcp", headers: [:], query: "key=\(token.dropLast())") == .invalidToken)
        #expect(gate.refusal(path: "/mcp", headers: [:], query: "key=\(token)x") == .invalidToken)
    }

    @Test(arguments: ["Origin", "Sec-Fetch-Site", "Sec-Fetch-Dest"])
    func refusesBrowserMarkedRequestsEvenWithAValidToken(_ header: String) {
        let headers = ["Authorization": "Bearer \(token)", header: "http://evil.example"]
        #expect(gate.refusal(path: "/mcp", headers: headers, query: nil) == .browserRequest)
    }

    /// Node's `fetch` sends `Sec-Fetch-Mode` on its own, so it cannot mark a caller as a browser
    /// without locking out the bundled Claude Desktop connector.
    @Test func secFetchModeAloneIsNotABrowserMarker() {
        let headers = ["Authorization": "Bearer \(token)", "Sec-Fetch-Mode": "cors"]
        #expect(gate.refusal(path: "/mcp", headers: headers, query: nil) == nil)
    }

    /// Loopback origins are refused too — nothing METAG serves is ever loaded in a browser.
    @Test func refusesLoopbackOrigin() {
        let headers = ["Authorization": "Bearer \(token)", "Origin": "http://127.0.0.1:19789"]
        #expect(gate.refusal(path: "/mcp", headers: headers, query: nil) == .browserRequest)
    }

    @Test func metadataPathStaysReachableWithoutATokenButNotFromABrowser() {
        let path = "/.well-known/oauth-protected-resource"
        #expect(gate.refusal(path: path, headers: [:], query: nil) == nil)
        #expect(gate.refusal(path: path, headers: ["Origin": "http://evil.example"], query: nil) == .browserRequest)
    }

    @Test func emptyServerTokenNeverMatches() {
        let empty = MCPAccessGate(token: "")
        #expect(empty.refusal(path: "/mcp", headers: ["Authorization": "Bearer "], query: nil) == .invalidToken)
        #expect(empty.refusal(path: "/mcp", headers: [:], query: "key=") == .missingToken)
    }
}

struct MCPAccessTokenStoreTests {

    private func temporaryTokenURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-token-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("mcp-token")
    }

    @Test func generatesWellFormedTokens() {
        for _ in 0..<32 {
            let token = MCPAccessToken.generate()
            #expect(token.count == MCPAccessToken.encodedLength)
            #expect(MCPAccessToken.isWellFormed(token))
        }
    }

    @Test func generatedTokensAreDistinct() {
        let tokens = Set((0..<256).map { _ in MCPAccessToken.generate() })
        #expect(tokens.count == 256)
    }

    @Test func createsTokenFileOwnerReadableOnly() throws {
        let url = temporaryTokenURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let token = try MCPAccessToken.loadOrCreate(at: url)
        #expect(MCPAccessToken.isWellFormed(token))

        let mode = try #require(
            FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)
        #expect(mode.int16Value == 0o600)
    }

    @Test func reusesTheStoredTokenAcrossLoads() throws {
        let url = temporaryTokenURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let first = try MCPAccessToken.loadOrCreate(at: url)
        let second = try MCPAccessToken.loadOrCreate(at: url)
        #expect(first == second)
    }

    /// A corrupt file must never become a usable credential.
    @Test(arguments: ["", "   ", "not-a-token", String(repeating: "a", count: 200), "abc def"])
    func replacesMalformedStoredToken(_ contents: String) throws {
        let url = temporaryTokenURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)

        let token = try MCPAccessToken.loadOrCreate(at: url)
        #expect(MCPAccessToken.isWellFormed(token))
        #expect(token != contents)
    }

    @Test func rotateReplacesTheStoredToken() async throws {
        let url = temporaryTokenURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = MCPAccessTokenStore(fileURL: url)
        let before = try await store.current()
        let after = try await store.rotate()
        #expect(before != after)
        #expect(try await store.current() == after)
        #expect(try MCPAccessToken.loadOrCreate(at: url) == after)
    }
}
