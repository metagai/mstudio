import Foundation

/// METAG 网关客户端：登录态 JWT + 生成任务提交/轮询/下载。
/// 与 web 端同一套 REST 契约（gateway/src/main.rs），不经 Convex。
enum MetagGateway {
    static let baseURL = URL(string: ProcessInfo.processInfo.environment["METAG_BASE_URL"] ?? "https://api.metag.ai")!

    private static let tokenAccount = "metag.jwt"

    static var token: String? {
        get { KeychainStore.load(account: tokenAccount) }
        set {
            if let newValue { KeychainStore.save(newValue, account: tokenAccount) }
            else { KeychainStore.delete(account: tokenAccount) }
        }
    }

    static var isSignedIn: Bool { token != nil }

    struct Account: Decodable, Sendable {
        let sub: String
        let credits: Int
    }

    struct Job: Decodable, Sendable {
        struct Shot: Decodable, Sendable {
            let narration: String
            let video: String
            let audio: String
        }
        let job_id: String
        let status: String?
        let error: String?
        let shots: [Shot]
        let cover: String?
    }

    enum Failure: LocalizedError {
        case signedOut
        case insufficientCredits
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .signedOut: return "Sign in to METAG to generate."
            case .insufficientCredits: return "Not enough credits."
            case .http(let code): return "METAG request failed (\(code))."
            }
        }
    }

    static func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) throws -> URLRequest {
        guard let token else { throw Failure.signedOut }
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    static func send<T: Decodable>(_ req: URLRequest, as: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200..<300: return try JSONDecoder().decode(T.self, from: data)
        case 401:
            token = nil
            throw Failure.signedOut
        case 402: throw Failure.insufficientCredits
        default: throw Failure.http(code)
        }
    }

    static func account() async throws -> Account {
        try await send(request("api/v1/me"), as: Account.self)
    }

    /// 提交一句话生成；engine: local | cloud | seedance | hh
    static func submit(
        prompt: String,
        engine: String = "local",
        cover: Bool = false,
        shots: Int = 4,
        firstFrame: String? = nil
    ) async throws -> String {
        struct Response: Decodable { let job_id: String }
        var body: [String: Any] = ["prompt": prompt, "engine": engine, "cover": cover, "shots": shots]
        if let firstFrame { body["first_frame"] = firstFrame }
        let req = try request("api/v1/agent/generate", method: "POST", body: body)
        return try await send(req, as: Response.self).job_id
    }

    /// 取件票据：5 分钟一次性，避免把 7 天 JWT 写进 URL（会进日志/历史）
    static func fileTicket(job id: String) async throws -> String {
        struct Response: Decodable { let ticket: String }
        return try await send(request("api/v1/jobs/\(id)/ticket", method: "POST"), as: Response.self).ticket
    }

    /// 图生视频首帧上传，返回 frame_id（服务端内存盘，1 小时蒸发）
    static func uploadFrame(_ fileURL: URL) async throws -> String {
        struct Response: Decodable { let frame_id: String }
        guard let token else { throw Failure.signedOut }
        let data = try Data(contentsOf: fileURL)
        var req = URLRequest(url: baseURL.appendingPathComponent("api/v1/upload/frame"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = data
        return try await send(req, as: Response.self).frame_id
    }

    /// Stripe 结账页（plan: "sub" 订阅 | "pack" 加油包）。官网直分发，不走 MAS 免 30% 抽成。
    static func checkoutURL(plan: String) async throws -> String {
        struct Response: Decodable { let url: String }
        let req = try request("api/v1/billing/checkout", method: "POST", body: ["plan": plan])
        return try await send(req, as: Response.self).url
    }

    static func job(_ id: String) async throws -> Job {
        try await send(request("api/v1/jobs/\(id)"), as: Job.self)
    }

    /// 轮询至终态。取消由调用方通过 Task 取消传递。
    static func waitForCompletion(_ id: String, pollInterval: Duration = .seconds(3)) async throws -> Job {
        while true {
            try Task.checkCancellation()
            let job = try await self.job(id)
            switch job.status {
            case "done": return job
            case "failed": throw Failure.http(500)
            default: try await Task.sleep(for: pollInterval)
            }
        }
    }

    /// 下载镜头文件到临时目录，返回本地 URL。`name` 为 shots[i].video/audio。
    static func download(job id: String, name: String, to directory: URL) async throws -> URL {
        // 绝对 URL 说明结果已落 S3（付费档），直接取；否则走网关流式端点
        let url: URL
        if let absolute = URL(string: name), absolute.scheme != nil {
            url = absolute
        } else {
            guard let token else { throw Failure.signedOut }
            url = baseURL.appendingPathComponent("files/\(id)/\(name)")
                .appending(queryItems: [URLQueryItem(name: "token", value: token)])
        }
        let (temp, response) = try await URLSession.shared.download(from: url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw Failure.http(code) }
        let destination = directory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try FileManager.default.moveItem(at: temp, to: destination)
        return destination
    }
}
