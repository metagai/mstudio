import Foundation

/// 托管 Agent 对话：METAG 网关 JWT（Keychain）+ 供应商线格式 SSE。
/// 生成类工具不走这里，仍走 GenerationBackend → create_job，计费入口只有一条。
struct MetagAgentClient: AgentClient {
    let settings: AgentRunSettings

    func stream(
        system: String,
        tools: [AgentToolSchema],
        messages: [AgentRequestMessage],
        context: AgentRequestContext
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        makeAgentStream { continuation in
            try await run(
                system: system,
                tools: tools,
                messages: messages,
                context: context,
                continuation: continuation
            )
        }
    }

    private func run(
        system: String,
        tools: [AgentToolSchema],
        messages: [AgentRequestMessage],
        context: AgentRequestContext,
        continuation: AsyncThrowingStream<AgentStreamEvent, Error>.Continuation
    ) async throws {
        let endpoint = MetagGateway.baseURL.appendingPathComponent("api/v1/agent/stream")
        guard let jwt = MetagGateway.token, !jwt.isEmpty else {
            throw AgentServiceError.unauthenticated
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("text/event-stream", forHTTPHeaderField: "accept")
        context.apply(to: &request, telemetryEnabled: Analytics.isEnabled)
        request.httpBody = try JSONSerialization.data(
            withJSONObject: settings.requestBody(system: system, tools: tools, messages: messages),
            options: [.sortedKeys]
        )

        let bytes: URLSession.AsyncBytes
        do {
            bytes = try await AgentHTTP.bytes(for: request) { status, body in
                AgentServiceError.from(status: status, body: body)
            }
        } catch let error as AgentServiceError {
            // 网关判定登录态失效时丢弃本地 JWT，避免面板反复撞 401
            if case .unauthenticated = error { MetagGateway.token = nil }
            throw error
        }
        try await settings.model.provider.parseSSE(bytes: bytes, continuation: continuation)
    }
}

enum AgentServiceError: LocalizedError {
    case unauthenticated
    case insufficientCredits(String)
    case unavailable(AgentModel)
    case refusal(AgentModel)
    case upstream(String)

    var errorDescription: String? {
        switch self {
        case .unauthenticated: L10n.key("Sign in to use the AI agent.")
        case .insufficientCredits(let m), .upstream(let m): m
        // 模型名是产品名词，不进翻译串；本地化的是它前后那句话
        case .unavailable(let model): "\(model.displayName): " + L10n.key("unavailable right now.")
        case .refusal(let model): "\(model.displayName): " + L10n.key("declined this request.")
        }
    }

    static func from(status: Int, body: String) -> AgentServiceError {
        let parsed = parseErrorEnvelope(body)
        let message = parsed?.message ?? body.prefix(500).description
        switch parsed?.code {
        case "unauthenticated": return .unauthenticated
        case "insufficient_credits": return .insufficientCredits(message)
        default:
            if status == 401 { return .unauthenticated }
            if status == 402 { return .insufficientCredits(message) }
            return .upstream(message.isEmpty ? "HTTP \(status)" : message)
        }
    }

    private static func parseErrorEnvelope(_ body: String) -> (code: String, message: String)? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let err = json["error"] as? [String: Any],
              let code = err["code"] as? String,
              let message = err["message"] as? String
        else { return nil }
        return (code, message)
    }
}
