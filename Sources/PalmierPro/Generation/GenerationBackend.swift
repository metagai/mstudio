import Foundation
import Combine
@preconcurrency import ConvexMobile

/// The RPC layer for the backend — METAG 网关（REST + 轮询），取代原 Convex 订阅。
/// 签名保持不变，`GenerationService` 的编排/占位/下载/撤销逻辑一行未动。
@MainActor
enum GenerationBackend {
    private static let pollInterval: TimeInterval = 3

    static func subscribe(
        jobId: String
    ) -> AnyPublisher<BackendGenerationJob?, Never>? {
        let subject = PassthroughSubject<BackendGenerationJob?, Never>()
        let task = Task {
            while !Task.isCancelled {
                do {
                    let job = try await MetagGateway.job(jobId)
                    let update = BackendGenerationJob(
                        _id: jobId,
                        status: status(from: job.status),
                        resultUrls: job.shots.isEmpty ? nil : job.shots.map { fileURL(job: jobId, name: $0.video) },
                        errorMessage: job.error,
                        costCredits: nil,
                        refundedCredits: nil,
                        completedAt: nil
                    )
                    subject.send(update)
                    if update.status == .succeeded || update.status == .failed {
                        subject.send(completion: .finished)
                        return
                    }
                } catch {
                    subject.send(
                        BackendGenerationJob(
                            _id: jobId,
                            status: .failed,
                            resultUrls: nil,
                            errorMessage: error.localizedDescription,
                            costCredits: nil,
                            refundedCredits: nil,
                            completedAt: nil
                        )
                    )
                    subject.send(completion: .finished)
                    return
                }
                try? await Task.sleep(for: .seconds(pollInterval))
            }
        }
        return subject
            .handleEvents(receiveCancel: { task.cancel() })
            .eraseToAnyPublisher()
    }

    private static func status(from raw: String?) -> BackendGenerationStatus {
        switch raw {
        case "done": return .succeeded
        case "failed": return .failed
        case "queued", nil: return .queued
        default: return .running
        }
    }

    /// 免费档结果留在网关内存盘，取件需带 token（<video>/下载器无法设 header）
    private static func fileURL(job: String, name: String) -> String {
        if let absolute = URL(string: name), absolute.scheme != nil { return name }
        let token = MetagGateway.token ?? ""
        return MetagGateway.baseURL
            .appendingPathComponent("files/\(job)/\(name)")
            .appending(queryItems: [URLQueryItem(name: "token", value: token)])
            .absoluteString
    }

    static func subscribeToProjectActivity(
        projectId: String
    ) -> AnyPublisher<[BackendProjectActivityEntry], ClientError>? {
        guard let convex = AccountService.shared.convex else { return nil }
        return convex.subscribe(
            to: "generations:projectActivity",
            with: ["projectId": projectId],
            yielding: [BackendProjectActivityEntry].self,
        )
    }

    static func uploadReference(
        fileURL: URL,
        contentType: String,
    ) async throws -> String {
        // 参考图/视频需要用户素材上传到云端 —— 与"素材不出设备"冲突，暂不开放
        throw BackendError.notConfigured
    }

    static func submit(
        model: String,
        params: BackendGenerationParams,
        projectId: String? = nil,
    ) async throws -> String {
        guard let prompt = params.prompt, !prompt.isEmpty else { throw BackendError.notConfigured }
        // macOS 端是"生成一个镜头"的意图，按镜头计价
        return try await MetagGateway.submit(prompt: prompt, engine: engine(for: model), shots: 1)
    }

    /// 模型 id → METAG 引擎档位。未知模型走本地档（最便宜，不会意外扣大额）。
    static func engine(for model: String) -> String {
        let id = model.lowercased()
        if id.contains("seedance") { return "seedance" }
        if id.contains("happyhorse") || id.contains("hh") { return "hh" }
        if id.contains("wan") || id.contains("cloud") { return "cloud" }
        return "local"
    }

    static func enhanceDraft(sourceJobId: String) async throws -> String {
        guard let convex = AccountService.shared.convex else {
            throw BackendError.notConfigured
        }
        let result: SubmitGenerationResult = try await convex.mutation(
            "generations:enhanceDraft",
            with: ["sourceJobId": sourceJobId],
        )
        return result.jobId
    }
}

// MARK: - Backend generation types

enum BackendGenerationParams: Encodable, Sendable {
    case video(VideoGenerationParams)
    case image(ImageGenerationParams)
    case audio(AudioGenerationParams)
    case upscale(UpscaleGenerationParams)

    var prompt: String? {
        switch self {
        case .video(let p): return p.prompt
        case .image(let p): return p.prompt
        case .audio(let p): return p.prompt
        case .upscale: return nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .video(let p): try c.encode(p)
        case .image(let p): try c.encode(p)
        case .audio(let p): try c.encode(p)
        case .upscale(let p): try c.encode(p)
        }
    }
}

enum BackendGenerationStatus: String, Decodable, Sendable {
    case queued, running, succeeded, failed
}

struct BackendGenerationJob: Decodable, Sendable {
    let _id: String
    let status: BackendGenerationStatus
    let resultUrls: [String]?
    let errorMessage: String?
    let costCredits: Int?
    let refundedCredits: Int?
    let completedAt: Double?
}

struct BackendProjectActivityEntry: Decodable, Sendable, Identifiable {
    enum Kind: String, Decodable, Sendable {
        case generation
        case failed
        case refund
    }

    let id: String
    let kind: Kind
    let model: String
    let credits: Int
    let createdAt: Double

    var creditImpact: Int {
        kind == .refund ? -credits : credits
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: createdAt / 1_000)
    }
}

private struct UrlResponse: Decodable, Sendable {
    let url: String
}

private struct SubmitGenerationResult: Decodable, Sendable {
    let jobId: String
}
