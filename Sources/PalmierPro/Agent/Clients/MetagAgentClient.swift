import Foundation

/// 托管 Agent 对话：METAG 网关 JWT（Keychain）+ 供应商线格式 SSE。
/// 生成类工具不走这里，仍走 GenerationBackend → create_job，计费入口只有一条。
struct MetagAgentClient: AgentClient {
    /// 托管对话的端点。常量化是为了让守卫盯得住它 —— 网关改路径时测试会红。
    static let path = "api/v1/agent/stream"

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
        let endpoint = MetagGateway.baseURL.appendingPathComponent(Self.path)
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

    /// 网关**没按约定回错误信封**时，屏幕上写什么。
    ///
    /// 上一版写的是 `body.prefix(500)` —— 而不按信封回的那些情况，
    /// body 恰恰是**最不能给人看的东西**：nginx 的 502 HTML、
    /// 网关的堆栈、一段截断到一半的 JSON。他在聊天框里读到 500 个字符的源码。
    ///
    /// 原始 body 进日志，不进屏幕。状态码留在句子里 —— 它短，而且找我们时有用。
    nonisolated static func fallbackMessage(status: Int) -> String {
        switch status {
        case 408, 504: return L10n.string("The request timed out. Try again.")
        case 429: return L10n.string("Too many requests right now — give it a moment and try again.")
        case 500...599: return L10n.string("Something went wrong on our side. Try again in a moment.")
        default: return L10n.string("That request didn't go through (HTTP \(status)).")
        }
    }

    static func from(status: Int, body: String) -> AgentServiceError {
        let parsed = parseErrorEnvelope(body)
        if parsed == nil, !body.isEmpty {
            Log.agent.error("agent error body not an envelope status=\(status) body=\(body.prefix(500))")
        }
        let message = parsed?.message ?? fallbackMessage(status: status)
        switch parsed?.code {
        case "unauthenticated": return .unauthenticated
        case "insufficient_credits": return .insufficientCredits(message)
        default:
            if status == 401 { return .unauthenticated }
            if status == 402 { return .insufficientCredits(message) }
            return .upstream(message.isEmpty ? fallbackMessage(status: status) : message)
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
