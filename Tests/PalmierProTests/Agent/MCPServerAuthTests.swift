import Darwin
import Foundation
import MCP
import Testing

@testable import PalmierPro

/// End-to-end over a real loopback socket: the token is enforced on the wire, not only in the
/// gate type, and no response ever carries a CORS grant.
@Suite(.serialized) struct MCPServerAuthTests {

    private static let initializeBody =
        #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}"#

    private func makeServer(port: UInt16, token: String) -> MCPHTTPServer {
        MCPHTTPServer(port: port, token: token) {
            let server = Server(
                name: "test",
                version: "1.0.0",
                capabilities: .init(tools: .init(listChanged: true))
            )
            await server.withMethodHandler(ListTools.self) { _ in
                .init(tools: [Tool(name: "probe", description: "probe", inputSchema: .object([:]))])
            }
            return MCPServerInstance(server: server) { _ in }
        }
    }

    private func post(
        port: UInt16,
        body: String = MCPServerAuthTests.initializeBody,
        extraHeaders: [String] = [],
        query: String = "",
        method: String = "POST"
    ) async throws -> RawHTTPResponse {
        var lines = [
            "\(method) /mcp\(query) HTTP/1.1",
            "Host: 127.0.0.1:\(port)",
            "Content-Type: application/json",
            "Accept: application/json, text/event-stream",
            "Content-Length: \(body.utf8.count)",
        ]
        lines.append(contentsOf: extraHeaders)
        return try await RawHTTP.send(lines.joined(separator: "\r\n") + "\r\n\r\n" + body, toPort: port)
    }

    @Test func refusesRequestsWithoutAToken() async throws {
        let port = MCPTestPort.reserve()
        let server = makeServer(port: port, token: MCPAccessToken.generate())
        try await server.start()
        defer { Task { await server.stop() } }

        let response = try await post(port: port)
        #expect(response.statusCode == 403)
        #expect(response.body.contains("missing METAG access token"))
        #expect(response.header("Access-Control-Allow-Origin") == nil)
    }

    @Test func refusesRequestsWithAWrongToken() async throws {
        let port = MCPTestPort.reserve()
        let server = makeServer(port: port, token: MCPAccessToken.generate())
        try await server.start()
        defer { Task { await server.stop() } }

        let response = try await post(
            port: port, extraHeaders: ["Authorization: Bearer \(MCPAccessToken.generate())"])
        #expect(response.statusCode == 403)
        #expect(response.body.contains("not valid"))
    }

    @Test func acceptsTheBearerToken() async throws {
        let port = MCPTestPort.reserve()
        let token = MCPAccessToken.generate()
        let server = makeServer(port: port, token: token)
        try await server.start()
        defer { Task { await server.stop() } }

        let response = try await post(port: port, extraHeaders: ["Authorization: Bearer \(token)"])
        #expect(response.statusCode == 200)
        #expect(response.body.contains("protocolVersion"))
        #expect(response.header("Access-Control-Allow-Origin") == nil)
    }

    @Test func acceptsTheQueryKey() async throws {
        let port = MCPTestPort.reserve()
        let token = MCPAccessToken.generate()
        let server = makeServer(port: port, token: token)
        try await server.start()
        defer { Task { await server.stop() } }

        let response = try await post(port: port, query: "?key=\(token)")
        #expect(response.statusCode == 200)
        #expect(response.body.contains("protocolVersion"))
    }

    /// A page that talked the user into pasting the token still gets nothing.
    @Test func refusesBrowserOriginatedRequestsHoldingAValidToken() async throws {
        let port = MCPTestPort.reserve()
        let token = MCPAccessToken.generate()
        let server = makeServer(port: port, token: token)
        try await server.start()
        defer { Task { await server.stop() } }

        let response = try await post(
            port: port,
            extraHeaders: [
                "Authorization: Bearer \(token)",
                "Origin: https://evil.example",
                "Sec-Fetch-Site: cross-site",
                "Sec-Fetch-Dest: empty",
            ]
        )
        #expect(response.statusCode == 403)
        #expect(response.body.contains("web page"))
        #expect(response.header("Access-Control-Allow-Origin") == nil)
    }

    /// Without a preflight grant the browser never sends the real request.
    @Test func refusesCORSPreflight() async throws {
        let port = MCPTestPort.reserve()
        let server = makeServer(port: port, token: MCPAccessToken.generate())
        try await server.start()
        defer { Task { await server.stop() } }

        let response = try await RawHTTP.send(
            [
                "OPTIONS /mcp HTTP/1.1",
                "Host: 127.0.0.1:\(port)",
                "Origin: https://evil.example",
                "Access-Control-Request-Method: POST",
                "Access-Control-Request-Headers: content-type",
                "Content-Length: 0",
            ].joined(separator: "\r\n") + "\r\n\r\n",
            toPort: port
        )
        #expect(response.statusCode == 403)
        #expect(response.header("Access-Control-Allow-Origin") == nil)
        #expect(response.header("Access-Control-Allow-Methods") == nil)
    }

    @Test func rotationRevokesTheOldTokenAndItsLiveSession() async throws {
        let port = MCPTestPort.reserve()
        let token = MCPAccessToken.generate()
        let server = makeServer(port: port, token: token)
        try await server.start()
        defer { Task { await server.stop() } }

        let initialized = try await post(port: port, extraHeaders: ["Authorization: Bearer \(token)"])
        #expect(initialized.statusCode == 200)
        let sessionID = try #require(initialized.header("Mcp-Session-Id"))

        let rotated = MCPAccessToken.generate()
        await server.setToken(rotated)

        let withOldToken = try await post(
            port: port,
            body: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
            extraHeaders: ["Authorization: Bearer \(token)", "Mcp-Session-Id: \(sessionID)"]
        )
        #expect(withOldToken.statusCode == 403)

        // The new token is accepted, but the session that authenticated under the old one is gone.
        let withNewTokenOldSession = try await post(
            port: port,
            body: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
            extraHeaders: ["Authorization: Bearer \(rotated)", "Mcp-Session-Id: \(sessionID)"]
        )
        #expect(withNewTokenOldSession.statusCode == 404)

        let reinitialized = try await post(port: port, extraHeaders: ["Authorization: Bearer \(rotated)"])
        #expect(reinitialized.statusCode == 200)
    }
}

// MARK: - Port allocation

/// The server binds with `allowLocalEndpointReuse`, so two suites that draw the same random port
/// both bind it and steal each other's connections. Hand out distinct ports instead.
enum MCPTestPort {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var next = UInt16.random(in: 49_500...58_000)

    static func reserve() -> UInt16 {
        lock.lock()
        defer { lock.unlock() }
        next += 1
        return next
    }
}

// MARK: - Raw HTTP client

struct RawHTTPResponse {
    let statusCode: Int
    let headers: [(name: String, value: String)]
    let body: String

    func header(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

enum RawHTTPError: Error {
    case connectFailed(Int32)
    case writeFailed
    case malformedResponse
}

/// Deliberately not URLSession: the tests need to set `Origin` and read the exact bytes back.
enum RawHTTP {
    /// Blocking socket work must not run on Swift's cooperative pool — the rest of the suite
    /// saturates it, and a parked thread there stalls the very server being probed.
    private static let queue = DispatchQueue(label: "ai.metag.tests.rawhttp", attributes: .concurrent)

    static func send(_ request: String, toPort port: UInt16) async throws -> RawHTTPResponse {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try sendBlocking(request, toPort: port) })
            }
        }
    }

    private static func sendBlocking(_ request: String, toPort port: UInt16) throws -> RawHTTPResponse {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw RawHTTPError.connectFailed(errno) }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { throw RawHTTPError.connectFailed(errno) }

        // Generous: the whole suite runs in parallel and saturates the machine.
        var timeout = timeval(tv_sec: 60, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let outgoing = Array(request.utf8)
        guard write(descriptor, outgoing, outgoing.count) == outgoing.count else {
            throw RawHTTPError.writeFailed
        }

        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            if let complete = parse(received), complete.isComplete { break }
            let count = read(descriptor, &buffer, buffer.count)
            if count <= 0 { break }
            received.append(contentsOf: buffer[0..<count])
        }
        guard let parsed = parse(received) else { throw RawHTTPError.malformedResponse }
        return parsed.response
    }

    /// Stops reading once `Content-Length` bytes have arrived so keep-alive replies do not
    /// stall the test for the socket timeout.
    private static func parse(_ data: Data) -> (response: RawHTTPResponse, isComplete: Bool)? {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[data.startIndex..<separator.lowerBound], encoding: .utf8)
        else { return nil }

        let lines = head.components(separatedBy: "\r\n")
        guard let status = lines.first?.split(separator: " ").dropFirst().first,
              let statusCode = Int(status) else { return nil }

        let headers = lines.dropFirst().compactMap { line -> (name: String, value: String)? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            return (
                String(line[..<colon]).trimmingCharacters(in: .whitespaces),
                String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            )
        }

        let bodyData = data[separator.upperBound...]
        let response = RawHTTPResponse(
            statusCode: statusCode,
            headers: headers,
            body: String(decoding: bodyData, as: UTF8.self)
        )
        let declared = headers.first { $0.name.caseInsensitiveCompare("Content-Length") == .orderedSame }
            .flatMap { Int($0.value) }
        return (response, declared.map { bodyData.count >= $0 } ?? false)
    }
}
