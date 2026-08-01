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

    /// 托管 Agent 对话（MetagAgentClient）需要网关侧的 /api/v1/agent/chat。
    /// 该端点尚未上线：还缺模型供应商与按 token 的计价口径，两者都要创始人拍板。
    /// 端点上线后把默认值改成 true；本地联调用 METAG_HOSTED_AGENT=1 提前打开。
    static let hostedAgentEnabled = ProcessInfo.processInfo.environment["METAG_HOSTED_AGENT"] == "1"

    /// GET /api/v1/me 的全部字段。没有头像/档位名。
    struct Account: Decodable, Sendable {
        /// OAuth 的 `provider:id`。内部标识 —— 永远不要显示给用户。
        let sub: String
        let credits: Int
        /// 付费与否的唯一判据（网关 users.sub_until > now），客户端不要自己推断
        let subscribed: Bool
        /// 网关只回已验证的邮箱；未验证时为 nil，不能当身份凭据用。
        let email: String?
        let email_verified: Bool?
    }

    /// GET /api/v1/pricing —— 单价真源，无需认证。只解我们用得到的字段。
    struct Pricing: Decodable, Sendable {
        struct Plan: Decodable, Sendable, Identifiable {
            let id: String          // sub | pro | studio | pack
            let price_usd: Double
            let interval: String    // month | once
            let credits: Int

            var isSubscription: Bool { interval == "month" }
        }
        /// One generation engine. Billing is flat per shot — `credits_per_shot` is what the
        /// gateway actually charges. `duration_s` / `resolution` are structured on purpose:
        /// deriving billing numbers from the display string `spec` broke silently on a reword.
        struct Engine: Decodable, Sendable, Identifiable {
            let id: String
            let name: String
            let name_i18n: [String: String]?
            let spec: String
            let resolution: String?
            let duration_s: Int?
            let native_audio: Bool
            let credits_per_shot: Int
            /// 这一档吃不吃用户上传的图。**不是所有档都吃** ——
            /// seedance / veo / cloud 的提交体里只有 prompt，图会被静默丢弃，
            /// 而用户按 26~60 credits/镜付了钱，成片却和他的图毫无关系。
            /// 老网关不回这个字段时按 true 处理：宁可让网关去拦，也不要误挡住可用的档。
            /// 默认 nil：新增的可选字段不该逼所有构造点改一遍；
            /// 老网关不回这个字段时也自然落到「按可用处理」。
            var accepts_image: Bool? = nil
            var acceptsImage: Bool { accepts_image ?? true }

            /// Display name for `code` (`zh` | `en` | `es`), falling back to the legacy `name`.
            func displayName(for code: String) -> String {
                name_i18n?[code] ?? name_i18n?["en"] ?? name
            }
        }
        let signup_free_credits: Int
        let plans: [Plan]
        let engines: [Engine]
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
        /// Shots finish serially (~36s each), so fill placeholders as they land.
        let shots_done: Int?
        /// Per-shot re-shoot state: queued / running / done / "failed: …", nil when never re-shot.
        let reshoot: [String?]?
        /// Per-shot takes, best first. The delivered take is always element 0.
        let alts: [[Take]]?
        /// Per-shot quality score. Below 0.75 the gate thinks the shot is broken.
        let scores: [Double?]?

        struct Take: Decodable, Sendable {
            let file: String
            let score: Double
        }
    }

    enum Failure: LocalizedError {
        case signedOut
        case insufficientCredits
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .signedOut: return L10n.key("Sign in to METAG to generate.")
            case .insufficientCredits: return L10n.key("Not enough credits.")
            case .http(let code): return L10n.key("METAG request failed.") + " (\(code))"
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

    /// 价格与赠额的单价真源。无需登录 —— 登录页也要报出赠额，所以不能挂在 JWT 上。
    /// 我的作品。**这个接口此前不存在** —— 用户只能靠自己还留着的深链打开某一单，
    /// 关掉窗口就再也找不回来，而 credits 已经扣了。
    /// 数据全部来自服务端的 PostgreSQL（持久），不读 Redis：
    /// 那里的任务 24 小时后就没了，而"我买过什么"必须比那久得多。
    struct FilmRow: Decodable, Sendable, Identifiable {
        let job_id: String
        let status: String
        let engine: String
        let shots: Int
        let credits: Int
        let created_at: Double
        let prompt: String?
        /// 产物还取不取得到。**扣了钱就必须取得到** ——
        /// 取不到要如实标出，不能假装能打开。
        let retrievable: Bool
        var id: String { job_id }
    }

    /// 额度流水。**这张表此前只写不读** —— 用户看不到自己的钱去哪了。
    /// 2026-08-01 的事故里我们弄丢了一位用户付过钱的成片、退了额度、重出了一版，
    /// 而他在产品里没有任何地方能看到这件事发生过。信任不会因为修好了就自动回来。
    ///
    /// 服务端只回枚举，文案在客户端本地化 —— 服务端拼中文，英文界面上就会冒出中文。
    struct CreditEntry: Decodable, Sendable, Identifiable {
        let at: Double
        let reason: String
        let delta: Int
        let job_id: String?
        /// 到期后 prompt 会被隐私清扫抹掉，那时没有标题可显示
        let title: String?
        var id: String { "\(at)-\(reason)-\(delta)" }
    }

    static func creditActivity() async throws -> [CreditEntry] {
        struct Response: Decodable { let items: [CreditEntry] }
        return try await send(request("api/v1/credits/activity"), as: Response.self).items
    }

    static func myFilms() async throws -> [FilmRow] {
        struct Response: Decodable { let jobs: [FilmRow] }
        return try await send(request("api/v1/jobs"), as: Response.self).jobs
    }

    // ---------- 免费草案：先看片，再决定付不付钱 ----------
    //
    // web 端一直有这条路，macOS 端此前没有 —— 用户从生成对话框直接走付费出片。
    // 而"先看后买"正是首页对外的承诺，两端不一致等于对一半用户失约。

    /// 起草。0 credits。`firstFrame` 给了就用它当第 0 镜的首帧，
    /// 后续镜头靠 continuity 把同一主体带下去。
    static func preview(
        prompt: String,
        shots: Int = 4,
        firstFrame: String? = nil
    ) async throws -> String {
        struct Response: Decodable { let job_id: String }
        var body: [String: Any] = [
            "prompt": prompt, "shots": shots,
            "lang": await currentLanguageCode(),
        ]
        if let firstFrame { body["first_frame"] = firstFrame }
        return try await send(request("api/v1/preview", method: "POST", body: body), as: Response.self).job_id
    }

    /// 逐镜修改草案，仍然 0 credits。**只重做被改的那几镜** ——
    /// 改一个字就全片重来，"修改"就等于"重来"，也就失去了意义。
    struct ReviseEdit: Encodable, Sendable {
        let index: Int
        var narration: String?
        var reroll: Bool?
    }

    static func revisePreview(id: String, edits: [ReviseEdit]) async throws {
        struct Ack: Decodable { let status: String? }
        let data = try JSONEncoder().encode(["edits": edits])
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        _ = try await send(request("api/v1/preview/\(id)/revise", method: "POST", body: obj), as: Ack.self)
    }

    /// 确认出片：**此刻才计费**，从用户看过的那批首帧出发。
    static func approvePreview(id: String, engine: String, allShots: Bool = false) async throws -> String {
        struct Response: Decodable { let job_id: String }
        var body: [String: Any] = ["engine": engine]
        // 用户选的引擎是**上限**：默认只有需要口型同步的镜头才用它，其余降到 local。
        // allShots 打开时每一镜都用 —— 否则最贵的档对没有口播的片子实际上买不到。
        if allShots { body["all_shots"] = true }
        return try await send(request("api/v1/preview/\(id)/approve", method: "POST", body: body),
                              as: Response.self).job_id
    }

    static func pricing() async throws -> Pricing {
        try await send(URLRequest(url: baseURL.appendingPathComponent("api/v1/pricing")), as: Pricing.self)
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
        var body: [String: Any] = [
            "prompt": prompt, "engine": engine, "cover": cover, "shots": shots,
            // 旁白语言跟随界面语言。每个建单入口都要带，否则用户会遇到"有时中文有时英文"。
            // 画面 prompt 保持英文 —— 那是视频模型的要求，不是用户偏好。
            "lang": await currentLanguageCode(),
        ]
        if let firstFrame { body["first_frame"] = firstFrame }
        let req = try request("api/v1/agent/generate", method: "POST", body: body)
        return try await send(req, as: Response.self).job_id
    }

    /// 界面语言 → 网关 `lang`。集中在这里，避免各建单入口各自取值而漏掉。
    static func currentLanguageCode() async -> String {
        await MainActor.run {
            AppLocalization.shared.selection.identifier
                ?? Locale.current.language.languageCode?.identifier ?? "en"
        }
    }

    /// 取件票据：5 分钟一次性，避免把 7 天 JWT 写进 URL（会进日志/历史）
    /// Rebuild a film from a storyboard we already have, skipping the LLM.
    static func submitStoryboard(title: String, prompts: [String], narrations: [String]) async throws -> String {
        struct Response: Decodable { let job_id: String }
        let body: [String: Any] = [
            "prompt": title,
            "engine": "local",
            "shots": prompts.count,
            "lang": await currentLanguageCode(),
            "storyboard": ["video_prompts": prompts, "narrations": narrations],
        ]
        let req = try request("api/v1/agent/generate", method: "POST", body: body)
        return try await send(req, as: Response.self).job_id
    }

    /// Re-run only the shots the quality gate flagged, keeping what you have as a take.
    struct Converged: Decodable, Sendable {
        struct Skip: Decodable, Sendable {
            let shot: Int
            let score: Double?
            let reason: String
        }
        let queued: [Int]
        let skipped: [Skip]
    }

    static func converge(job id: String, rounds: Int, candidates: Int) async throws -> Converged {
        let req = try request(
            "api/v1/jobs/\(id)/converge",
            method: "POST",
            body: ["rounds": rounds, "candidates": candidates]
        )
        return try await send(req, as: Converged.self)
    }

    /// Re-shoot one shot of a finished film. The delivered take is never overwritten —
    /// the result arrives as an extra take, so the choice stays reversible.
    static func reshoot(job id: String, shot: Int, reroll: Bool, candidates: Int) async throws {
        var body: [String: Any] = ["shot": shot, "candidates": candidates]
        if reroll { body["reroll"] = true }
        let req = try request("/api/v1/jobs/\(id)/reshoot", method: "POST", body: body)
        struct Response: Decodable { let status: String }
        _ = try await send(req, as: Response.self)
    }

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
