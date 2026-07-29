import Foundation
import MCP

/// HTTP adapter. Tool handling lives in `ToolExecutor`.
@Observable
@MainActor
final class MCPService {

    static let port: UInt16 = 19789

    private static let enabledKey = "ai.metag.mcp.enabled"

    static var isEnabledPreference: Bool {
        get {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: enabledKey) == nil { return true }
            return defaults.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
        }
    }

    private(set) var isRunning: Bool = false

    /// Set when an agent is turned away for a missing or stale token, so the UI can explain the
    /// break instead of letting a previously working connection fail silently.
    private(set) var lastRefusal: MCPAccessRefusal?
    private(set) var refusalCount: Int = 0

    @ObservationIgnored
    private let projectProvider: () -> VideoProject?
    @ObservationIgnored
    private var httpServer: MCPHTTPServer?
    @ObservationIgnored
    private var announcedRefusal = false
    /// Bumped by every start and stop so a token load that finishes after `stop()` cannot
    /// resurrect the listener.
    @ObservationIgnored
    private var lifecycleGeneration = 0

    init(projectProvider: @escaping () -> VideoProject?) {
        self.projectProvider = projectProvider
    }

    func start() {
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let token = try await MCPAccessTokenStore.shared.current()
                guard generation == lifecycleGeneration else { return }
                try await startServer(token: token)
            } catch {
                // No token means no way to authenticate callers, so the port stays closed.
                Log.mcp.error("http server not started: \(Log.detail(error))")
                isRunning = false
            }
        }
    }

    private func startServer(token: String) async throws {
        let httpServer = MCPHTTPServer(
            port: Self.port,
            token: token,
            onRefusal: { refusal in
                Task { @MainActor in AppState.shared.mcpService?.recordRefusal(refusal) }
            }
        ) { [self] in
            let toolExecutor = await makeSessionToolExecutor()
            let server = Server(
                name: "metag-mac",
                version: "1.0.0",
                instructions: AgentInstructions.serverInstructions + AgentInstructions.projectNavigation,
                capabilities: .init(
                    resources: .init(subscribe: false, listChanged: false),
                    tools: .init(listChanged: true)
                )
            )
            await Self.registerTools(on: server, executor: toolExecutor)
            await Self.registerResources(on: server)
            return MCPServerInstance(server: server) { clientInfo in
                await toolExecutor.setMCPClientInfo(MCPClientInfo(clientInfo))
            }
        }
        self.httpServer = httpServer
        try await httpServer.start()
        Log.mcp.notice("http server started port=\(Self.port)")
        isRunning = true
    }

    /// Issues a new token and revokes the old one everywhere it is still accepted.
    func rotateAccessToken() async throws -> String {
        let token = try await MCPAccessTokenStore.shared.rotate()
        await httpServer?.setToken(token)
        lastRefusal = nil
        refusalCount = 0
        announcedRefusal = false
        return token
    }

    func recordRefusal(_ refusal: MCPAccessRefusal) {
        lastRefusal = refusal
        refusalCount += 1
        guard !announcedRefusal else { return }
        announcedRefusal = true
        AppNotifications.mcpAgentRefused(refusal)
    }

    func makeSessionToolExecutor() -> ToolExecutor {
        ToolExecutor(projectProvider: projectProvider)
    }

    func stop() {
        lifecycleGeneration += 1
        if let server = httpServer {
            Task { await server.stop() }
        }
        httpServer = nil
        isRunning = false
        Log.mcp.notice("http server stopped")
    }

    nonisolated static func registerTools(on server: Server, executor: ToolExecutor) async {
        let tools: [Tool] = ToolDefinitions.mcpServer.map { def in
            Tool(name: def.name.rawValue, description: def.description, inputSchema: def.mcpSchemaValue)
        }

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: tools)
        }

        await server.withMethodHandler(CallTool.self) { params in
            await dispatchCall(params, executor: executor)
        }
    }

    // Convert args on the main actor so the non-Sendable dict never crosses the hop.
    private static func dispatchCall(_ params: CallTool.Parameters, executor: ToolExecutor) async -> CallTool.Result {
        let args = ToolArgsBridge.argsFromMCP(params.arguments ?? [:])
        let result = await executor.execute(name: params.name, args: args, source: "mcp")
        return result.toMCPResult()
    }

    private nonisolated static func registerResources(on server: Server) async {
        let resources = [
            Resource(
                name: "Video Models",
                uri: "metag://models/video",
                description: "Available AI video generation models and their capabilities",
                mimeType: "application/json"
            ),
            Resource(
                name: "Image Models",
                uri: "metag://models/image",
                description: "Available AI image generation models and their capabilities",
                mimeType: "application/json"
            ),
        ]

        await server.withMethodHandler(ListResources.self) { _ in
            .init(resources: resources)
        }

        await server.withMethodHandler(ReadResource.self) { params in
            await Self.readResource(uri: params.uri)
        }
    }

    @MainActor
    private static func readResource(uri: String) -> ReadResource.Result {
        switch uri {
        case "metag://models/video":
            let json = ToolExecutor.jsonString(VideoModelConfig.allModels.map { ToolExecutor.videoModelInfo($0) }) ?? "[]"
            return .init(contents: [.text(json, uri: uri, mimeType: "application/json")])
        case "metag://models/image":
            let json = ToolExecutor.jsonString(ImageModelConfig.allModels.map { ToolExecutor.imageModelInfo($0) }) ?? "[]"
            return .init(contents: [.text(json, uri: uri, mimeType: "application/json")])
        default:
            return .init(contents: [.text("Unknown resource: \(uri)", uri: uri)])
        }
    }

}
