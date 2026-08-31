import Foundation
import Combine

/// The RPC layer for the backend — METAG 网关（REST + 轮询），取代原 Convex 订阅。
/// 签名保持不变，`GenerationService` 的编排/占位/下载/撤销逻辑一行未动。
@MainActor
enum GenerationBackend {
    private static let pollInterval: TimeInterval = 3

    static func subscribe(
        jobId: String
    ) -> AnyPublisher<BackendGenerationJob?, Never>? {
        if let local = LocalJobs.subscribe(jobId) { return local }
        let subject = PassthroughSubject<BackendGenerationJob?, Never>()
        let task = Task {
            while !Task.isCancelled {
                do {
                    let job = try await MetagGateway.job(jobId)
                    let ticket = job.shots.isEmpty ? nil : try? await MetagGateway.fileTicket(job: jobId)
                    let update = BackendGenerationJob(
                        _id: jobId,
                        status: status(from: job.status),
                        resultUrls: job.shots.isEmpty ? nil : job.shots.map { fileURL(job: jobId, name: $0.video, ticket: ticket) },
                        errorMessage: job.error,
                        costCredits: nil,
                        refundedCredits: nil,
                        completedAt: nil,
                        readyCount: job.shots_done ?? 0
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
                            completedAt: nil,
                            readyCount: 0
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

    /// 免费档结果留在网关内存盘；下载器无法设 header，所以带短时效票据而不是长期 JWT
    private static func fileURL(job: String, name: String, ticket: String?) -> String {
        if let absolute = URL(string: name), absolute.scheme != nil { return name }
        return MetagGateway.baseURL
            .appendingPathComponent("files/\(job)/\(name)")
            .appending(queryItems: [URLQueryItem(name: "ticket", value: ticket ?? "")])
            .absoluteString
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
        // 本地出图：权重和算力都在这台机器上，不经过网关、不计费。
        if model == LocalImageBackend.modelId, case .image(let p) = params {
            return LocalJobs.start(prompt: p.prompt)
        }
        // METAG 网关目前只做视频。音频/图片/放大若静默走视频通道，用户会拿到不对的东西还被扣费 ——
        // 明确拒绝，比"看起来能用"诚实。
        guard case .video = params else { throw BackendError.unsupported }
        guard let prompt = params.prompt, !prompt.isEmpty else { throw BackendError.notConfigured }
        // 图生视频：起始帧是本地文件就先上传，与 web 端同一条 /upload/frame 契约
        var frameId: String?
        if case .video(let p) = params, let start = p.startFrameURL, let url = URL(string: start), url.isFileURL {
            frameId = try await MetagGateway.uploadFrame(url)
        }
        // 带了图却选了吃不下图的档，就当场说清楚，别让他白付钱。
        // seedance / veo / cloud 的提交体里只有 prompt —— 图会被静默丢弃，
        // 而按 26~60 credits/镜已经扣了。网关也会 400 拦一次，
        // 这里先拦是为了给出**能读懂的原因**，而不是一个 HTTP 状态码。
        let chosen = engine(for: model)
        if frameId != nil, let e = try? await MetagGateway.pricing().engines.first(where: { $0.id == chosen }),
           !e.acceptsImage {
            throw BackendError.imageNotSupported(engine: e.displayName(for: await MetagGateway.currentLanguageCode()))
        }
        // macOS 端是"生成一个镜头"的意图，按镜头计价
        return try await MetagGateway.submit(
            prompt: prompt,
            engine: chosen,
            shots: 1,
            firstFrame: frameId
        )
    }

    /// 模型 id → METAG 引擎档位。未知模型走本地档（最便宜，不会意外扣大额）。
    /// Upstream's draft-enhance runs on a Convex mutation the METAG gateway has no
    /// equivalent for. The catalog never sets the draft rates that surface the control,
    /// so this stays unreachable — and says so plainly if it ever is reached.
    static func enhanceDraft(sourceJobId: String) async throws -> String {
        throw BackendError.unsupported
    }

    static func engine(for model: String) -> String {
        let id = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return id.isEmpty ? "local" : id
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
    /// Shots available for download so far.
    /// 已经可下载的镜头数。网关不回这个字段时按 0 解 —— 旧任务不该整条解不出来。
    var readyCount: Int = 0

    enum CodingKeys: String, CodingKey {
        case _id, status, resultUrls, errorMessage, costCredits, refundedCredits, completedAt, readyCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try c.decode(String.self, forKey: ._id)
        status = try c.decode(BackendGenerationStatus.self, forKey: .status)
        resultUrls = try c.decodeIfPresent([String].self, forKey: .resultUrls)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        costCredits = try c.decodeIfPresent(Int.self, forKey: .costCredits)
        refundedCredits = try c.decodeIfPresent(Int.self, forKey: .refundedCredits)
        completedAt = try c.decodeIfPresent(Double.self, forKey: .completedAt)
        readyCount = try c.decodeIfPresent(Int.self, forKey: .readyCount) ?? 0
    }

    init(_id: String, status: BackendGenerationStatus, resultUrls: [String]?, errorMessage: String?,
         costCredits: Int?, refundedCredits: Int?, completedAt: Double?, readyCount: Int = 0) {
        self._id = _id; self.status = status; self.resultUrls = resultUrls
        self.errorMessage = errorMessage; self.costCredits = costCredits
        self.refundedCredits = refundedCredits; self.completedAt = completedAt; self.readyCount = readyCount
    }
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
