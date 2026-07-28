import Foundation

extension ToolExecutor {
    // send_feedback's diagnostics trail + per-session dedupe; recorded centrally in execute().
    struct FeedbackState {
        private(set) var recentTools: [String] = []
        private(set) var lastError: String?
        var sentKeys: Set<String> = []

        mutating func record(_ result: ToolResult, for tool: ToolName) {
            guard tool != .sendFeedback else { return }
            recentTools.append(tool.rawValue)
            if recentTools.count > 15 { recentTools.removeFirst() }
            if result.isError, case let .text(message)? = result.content.first { lastError = message }
        }

        mutating func recordError(_ message: String) {
            lastError = message
        }
    }

    func resetFeedbackState() { feedbackState = FeedbackState() }

    private static let feedbackCategories: Set<String> = [
        "missing_capability", "wrong_result", "confusing_ux", "failure", "suggestion",
    ]
    private static let feedbackSeverities: Set<String> = ["low", "medium", "high"]
    private static let maxFeedbackPerSession = 8

    func sendFeedback(_ editor: EditorViewModel, _ args: [String: Any]) async throws -> ToolResult {
        let category = try args.requireString("category").trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.feedbackCategories.contains(category) else {
            throw ToolError("Invalid category '\(category)'. Expected one of: \(Self.feedbackCategories.sorted().joined(separator: ", ")).")
        }
        let summary = try args.requireString("summary").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { throw ToolError("summary must not be empty.") }
        let details = args.string("details")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let severity = args.string("severity")?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let severity, !Self.feedbackSeverities.contains(severity) {
            throw ToolError("Invalid severity '\(severity)'. Expected low, medium, or high.")
        }

        _ = (details, severity, editor)
        // The METAG gateway has no feedback endpoint, so there is nowhere to deliver this.
        // Reported as a gap rather than silently succeeding.
        return .error("Feedback can't be sent from this build — tell the user to report it directly instead.")
    }
}
