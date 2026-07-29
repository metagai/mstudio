import Foundation

/// Why the MCP server refused a request. Every case is an explicit refusal; the gate has no
/// "could not tell, so allow" branch.
enum MCPAccessRefusal: String, Sendable {
    case browserRequest
    case missingToken
    case invalidToken

    var statusCode: Int { 403 }

    /// Machine-facing. Kept out of the localization catalog like every other MCP contract value.
    var message: String {
        switch self {
        case .browserRequest:
            "Forbidden: METAG does not accept requests originating from a web page."
        case .missingToken:
            "Forbidden: missing METAG access token. In METAG, open Help → MCP Instructions and copy the configuration for your agent."
        case .invalidToken:
            "Forbidden: the METAG access token is not valid. It may have been rotated. In METAG, open Help → MCP Instructions and copy the current configuration."
        }
    }
}

/// Decides whether a request may reach the MCP transport. Fails closed: a request is served
/// only when it presents the exact access token and carries no sign of a browser origin.
struct MCPAccessGate: Sendable {

    let token: String

    /// Carries no project data and no secret; stays reachable so a client that lost its token
    /// still gets a well-formed answer instead of a hang.
    static let publicPaths: Set<String> = ["/.well-known/oauth-protected-resource"]

    /// Headers a browser attaches on its own. Their presence is treated as proof the caller is a
    /// web page, whatever the `Origin` value says.
    ///
    /// `Sec-Fetch-Mode` is deliberately absent: Node's `fetch` sends it, so it would lock out the
    /// bundled Claude Desktop connector and every JavaScript MCP client. Measured against Chrome,
    /// `Origin`, `Sec-Fetch-Site`, and `Sec-Fetch-Dest` accompany every request a page can make,
    /// including `no-cors` posts, and no non-browser client observed sends them.
    private static let browserMarkers = ["origin", "sec-fetch-site", "sec-fetch-dest"]

    func refusal(path: String, headers: [String: String], query: String?) -> MCPAccessRefusal? {
        let lowercased = Dictionary(
            headers.map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )

        // Checked before the token: a page that tricked the user into pasting the token still loses.
        if Self.browserMarkers.contains(where: { lowercased[$0] != nil }) { return .browserRequest }

        if Self.publicPaths.contains(path) { return nil }

        if let authorization = lowercased["authorization"] {
            let parts = authorization.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2,
                  parts[0].caseInsensitiveCompare("Bearer") == .orderedSame else { return .invalidToken }
            let presented = parts[1].trimmingCharacters(in: .whitespaces)
            return MCPAccessToken.matches(presented, expected: token) ? nil : .invalidToken
        }

        guard let presented = Self.queryValue(named: "key", in: query) else { return .missingToken }
        return MCPAccessToken.matches(presented, expected: token) ? nil : .invalidToken
    }

    static func queryValue(named name: String, in query: String?) -> String? {
        guard let query, !query.isEmpty else { return nil }
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, parts[0] == name else { continue }
            let raw = String(parts[1])
            let decoded = raw.removingPercentEncoding ?? raw
            return decoded.isEmpty ? nil : decoded
        }
        return nil
    }
}
