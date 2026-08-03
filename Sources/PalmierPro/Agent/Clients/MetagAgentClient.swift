import Foundation

/// 托管 Agent 对话：METAG 网关 JWT（Keychain）+ Anthropic 线格式 SSE。
/// 生成类工具不走这里，仍走 GenerationBackend → create_job，计费入口只有一条。
struct MetagAgentClient: AgentClient {
    let model: AnthropicModel
    var maxTokens: Int { model.maxOutputTokens }

    static let path = "api/v1/agent/chat"

    func stream(
        system: String,
        tools: [AnthropicToolSchema],
        messages: [AnthropicMessage]
    ) -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(system: system, tools: tools, messages: messages, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        system: String,
        tools: [AnthropicToolSchema],
        messages: [AnthropicMessage],
        continuation: AsyncThrowingStream<AnthropicStreamEvent, Error>.Continuation
    ) async throws {
        guard let token = MetagGateway.token, !token.isEmpty else {
            throw AgentStreamError.unauthenticated
        }

        var request = URLRequest(url: MetagGateway.baseURL.appendingPathComponent(Self.path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("text/event-stream", forHTTPHeaderField: "accept")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: AnthropicRequestBody.build(
                model: model, maxTokens: maxTokens, system: system, tools: tools, messages: messages
            ),
            options: [.sortedKeys]
        )

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            var body = ""
            for try await line in bytes.lines { body += line + "\n" }
            let error = AgentStreamError.from(status: http.statusCode, body: body)
            // 网关判定登录态失效时丢弃本地 JWT，避免面板反复撞 401
            if case .unauthenticated = error { MetagGateway.token = nil }
            throw error
        }

        try await AnthropicSSE.parse(bytes: bytes, continuation: continuation)
    }
}

enum AgentStreamError: LocalizedError {
    case unauthenticated
    case insufficientCredits(String)
    case upstream(String)

    var errorDescription: String? {
        switch self {
        case .unauthenticated: "Sign in to use the AI agent."
        case .insufficientCredits(let m): m
        case .upstream(let m): m
        }
    }

    static func from(status: Int, body: String) -> AgentStreamError {
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
