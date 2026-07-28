import Foundation

/// 自动导演（D1）：主题 → 分镜 → 报价 → 用户确认 → 生成。
/// 花钱的一步永远等用户点头 —— `awaiting_approval` 时客户端不得自动 approve。
enum MetagDirector {
    struct Preset: Decodable, Sendable, Identifiable, Equatable {
        let id: String
        let name: String
        let tagline: String
        let pipeline: String
        let shots: Int
        let engine: String
        let target_seconds: Double
        let budget_credits: Int
        let estimated_cost_credits: Int
        let estimated_wait_seconds: Int

        /// mac 端能独立完成的流水线。footage-cut 需要端侧素材摘要与剪辑计划落地，尚未接入。
        var isSupported: Bool { pipeline == "short-form" || pipeline == "site-promo" }
        var needsURL: Bool { pipeline == "site-promo" }
    }

    struct Run: Decodable, Sendable, Equatable {
        struct Storyboard: Decodable, Sendable, Equatable {
            let narrations: [String]
        }
        struct Quote: Decodable, Sendable, Equatable {
            let stage: String
            let engine: String
            let shots: Int
            let cost_credits: Int
            let reason: String?
        }
        struct Site: Decodable, Sendable, Equatable {
            let title: String?
            let frame_id: String?
        }
        struct Artifacts: Decodable, Sendable, Equatable {
            var storyboard: Storyboard?
            var quote: Quote?
            var site: Site?
        }

        let id: String
        let pipeline: String
        let topic: String
        let status: String
        let stage: String
        let budget_credits: Int
        let spent_credits: Int
        let artifacts: Artifacts
        let job_id: String?
        let error: String?

        var isTerminal: Bool { status == "done" || status == "failed" || status == "cancelled" }
        var isAwaitingApproval: Bool { status == "awaiting_approval" }

        private enum CodingKeys: String, CodingKey {
            case id, pipeline, topic, status, stage, budget_credits, spent_credits, artifacts, job_id, error
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            pipeline = (try? c.decode(String.self, forKey: .pipeline)) ?? "short-form"
            topic = (try? c.decode(String.self, forKey: .topic)) ?? ""
            status = try c.decode(String.self, forKey: .status)
            stage = (try? c.decode(String.self, forKey: .stage)) ?? ""
            budget_credits = (try? c.decode(Int.self, forKey: .budget_credits)) ?? 0
            spent_credits = (try? c.decode(Int.self, forKey: .spent_credits)) ?? 0
            artifacts = (try? c.decode(Artifacts.self, forKey: .artifacts)) ?? Artifacts()
            job_id = try? c.decode(String.self, forKey: .job_id)
            error = try? c.decode(String.self, forKey: .error)
        }
    }

    /// 阶段进度条的标签，与网关的 stage 取值对应。
    static func stages(for pipeline: String) -> [(id: String, label: String)] {
        switch pipeline {
        case "site-promo":
            return [("capture", "Fetch Site"), ("storyboard", "Storyboard"), ("generate", "Generate"), ("done", "Done")]
        default:
            return [("storyboard", "Storyboard"), ("generate", "Generate"), ("deliver", "Deliver"), ("done", "Done")]
        }
    }
}

extension MetagGateway {
    /// 预设清单无需登录 —— 未登录也能先看清"多长、多少钱、多久"。
    static func directorPresets() async throws -> [MetagDirector.Preset] {
        struct Response: Decodable { let presets: [MetagDirector.Preset] }
        let req = URLRequest(url: baseURL.appendingPathComponent("api/v1/director/presets"))
        return try await send(req, as: Response.self).presets
    }

    static func startDirectorRun(
        preset: String,
        topic: String,
        url: String? = nil
    ) async throws -> MetagDirector.Run {
        var body: [String: Any] = ["preset": preset, "topic": topic]
        if let url, !url.isEmpty { body["url"] = url }
        return try await send(request("api/v1/director/runs", method: "POST", body: body), as: MetagDirector.Run.self)
    }

    static func directorRun(_ id: String) async throws -> MetagDirector.Run {
        try await send(request("api/v1/director/runs/\(id)"), as: MetagDirector.Run.self)
    }

    /// 只能由用户显式点击触发：这一步之后才扣费。
    static func approveDirectorRun(_ id: String) async throws -> MetagDirector.Run {
        try await send(request("api/v1/director/runs/\(id)/approve", method: "POST"), as: MetagDirector.Run.self)
    }

    static func cancelDirectorRun(_ id: String) async throws -> MetagDirector.Run {
        try await send(request("api/v1/director/runs/\(id)/cancel", method: "POST"), as: MetagDirector.Run.self)
    }
}
