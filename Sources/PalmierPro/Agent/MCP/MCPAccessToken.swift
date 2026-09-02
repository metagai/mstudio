import Foundation

/// Shared secret that gates the loopback MCP server.
///
/// Stored at `~/Library/Application Support/METAG/mcp-token` with mode `0600`, so only
/// processes running as the logged-in user can read it. Web pages cannot read files at all,
/// which is the boundary this closes: before the token, any page in any browser could drive
/// the whole timeline through `fetch("http://127.0.0.1:19789/mcp")`.
enum MCPAccessToken {

    /// 32 random bytes rendered as unpadded base64url.
    static let encodedLength = 43

    enum StoreError: LocalizedError {
        case unwritable(URL, any Error)

        var errorDescription: String? {
            switch self {
            case .unwritable(let url, let underlying):
                "Could not write the MCP access token to \(url.path): \(Log.detail(underlying))"
            }
        }
    }

    nonisolated static var fileURL: URL {
        AppIdentity.applicationSupportRoot.appendingPathComponent("mcp-token", isDirectory: false)
    }

    nonisolated static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &generator) }
        var encoded = Data(bytes).base64EncodedString()
        encoded = encoded.replacingOccurrences(of: "+", with: "-")
        encoded = encoded.replacingOccurrences(of: "/", with: "_")
        return String(encoded.prefix(while: { $0 != "=" }))
    }

    nonisolated static func isWellFormed(_ candidate: String) -> Bool {
        candidate.count == encodedLength && candidate.utf8.allSatisfy { byte in
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "-"), UInt8(ascii: "_"):
                true
            default:
                false
            }
        }
    }

    /// Call off the main thread. A malformed or unreadable file is replaced rather than trusted.
    nonisolated static func loadOrCreate(at url: URL = fileURL) throws -> String {
        let existed = FileManager.default.fileExists(atPath: url.path)
        if let data = FileManager.default.contents(atPath: url.path),
           let stored = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           isWellFormed(stored) {
            try? tightenPermissions(at: url)
            return stored
        }
        if existed {
            Log.mcp.warning("access token file is unreadable or malformed; issuing a replacement")
        }
        return try write(generate(), to: url)
    }

    /// Call off the main thread.
    nonisolated static func rotate(at url: URL = fileURL) throws -> String {
        try write(generate(), to: url)
    }

    /// Constant-time comparison so a local attacker cannot time-probe the token byte by byte.
    nonisolated static func matches(_ candidate: String, expected: String) -> Bool {
        let presented = Array(candidate.utf8)
        let known = Array(expected.utf8)
        guard !known.isEmpty, presented.count == known.count else { return false }
        var difference: UInt8 = 0
        for index in known.indices { difference |= presented[index] ^ known[index] }
        return difference == 0
    }

    @discardableResult
    private nonisolated static func write(_ token: String, to url: URL) throws -> String {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data(token.utf8).write(to: url, options: [.atomic])
            try tightenPermissions(at: url)
        } catch {
            throw StoreError.unwritable(url, error)
        }
        return token
    }

    private nonisolated static func tightenPermissions(at url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Serializes access to the on-disk token and keeps the in-memory copy authoritative for the
/// running server. Being an actor also keeps the file work off the main thread.
actor MCPAccessTokenStore {
    static let shared = MCPAccessTokenStore()

    private let fileURL: URL
    private var cached: String?

    init(fileURL: URL = MCPAccessToken.fileURL) {
        self.fileURL = fileURL
    }

    func current() throws -> String {
        if let cached { return cached }
        let token = try MCPAccessToken.loadOrCreate(at: fileURL)
        cached = token
        return token
    }

    func rotate() throws -> String {
        let token = try MCPAccessToken.rotate(at: fileURL)
        cached = token
        Log.mcp.notice("access token rotated; connected agents must be reconfigured")
        return token
    }
}
