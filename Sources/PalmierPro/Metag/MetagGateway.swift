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
            /// 这一档此刻能不能买。服务端探到上游或本地依赖坏掉时置 false ——
            /// **界面要提前禁用**，而不是让用户点下去拿一个 503。
            /// 老网关不回这个字段时按可售处理：把"不知道"当成"坏了"，
            /// 一次回滚就会让所有档位从界面上消失。
            var available: Bool? = nil
            var isAvailable: Bool { available ?? true }

            /// Display name for `code` (`zh` | `en` | `es`), falling back to the legacy `name`.
            func displayName(for code: String) -> String {
                name_i18n?[code] ?? name_i18n?["en"] ?? name
            }
        }
        let signup_free_credits: Int
        let plans: [Plan]
        let engines: [Engine]
        /// 非出片项的单价（voice_clone、image_edit、cover…）。
        /// 可选：老网关不回这个字段时不该让整个定价解不出来。
        var extras: [String: Int]? = nil
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
        /// 正在做哪一步（storyboard / voice / narration / frames / music）。
        /// **草案 84 秒里有 82 秒，状态只有"正在起草"四个字一动不动。**
        /// 机器码，文案在客户端 —— 本地化不进机器契约。
        let stage: String?
        /// 逐镜首帧。**等待期间用它把空白换成真实画面** ——
        /// 图早就画好了（草案阶段或出片时画的），只是从没回给过客户端。
        /// 盯着一个转圈和盯着自己片子的开场画面，是两种等待。
        let first_frames: [String]?
        /// Per-shot re-shoot state: queued / running / done / "failed: …", nil when never re-shot.
        let reshoot: [String?]?
        /// Per-shot takes, best first. The delivered take is always element 0.
        let alts: [[Take]]?
        /// Per-shot quality score. Below 0.75 the gate thinks the shot is broken.
        let scores: [Double?]?
        /// 当前旁白人格 id。界面文案在 MetagNarrator —— 契约里只有 id。
        let narrator: String?
        /// 逐镜实际使用的引擎。混档的片子（口播镜走 veo、空镜走 local）靠它逐镜判断，
        /// 整片一刀切会让无声档的那几镜变哑。确认出片之前不存在。
        let shot_engines: [String?]?
        /// **整单失败，但这几镜其实渲好了。** worker 归档后写下的镜号。
        /// 不认这个字段等于没抢救 —— 用户全额退了款，也一无所获。
        let salvaged: [Int]?
        /// 失败时额度退没退。用户在出事那一刻最想知道这个。
        let refunded: Bool?

        struct Take: Decodable, Sendable {
            let file: String
            let score: Double
        }
    }

    enum Failure: LocalizedError {
        case signedOut
        case insufficientCredits
        case http(Int)
        /// 带原因码的拒绝。**用户看到的必须是能据此行动的话，不是 "METAG request failed (429)"。**
        /// 两种 429 原来显示同一句：inflight_limit 是用户自己的正常状态，
        /// 却看起来像我们坏了。
        case rejected(Int, String)

        var errorDescription: String? {
            switch self {
            case .signedOut: return L10n.key("Sign in to METAG to generate.")
            case .insufficientCredits: return L10n.key("Not enough credits.")
            // 这几条以前全都落到下面那句 "METAG request failed (404)"，
            // 而**紧挨着的注释就写着**"用户看到的必须是能据此行动的话"。
            // 它们不是罕见情况，是最常见的那几种：打开昨天的链接、连点两次出片、
            // 传了一张大图、上游抖动。
            case .http(404):
                // 404 同时表示"过期"和"不是你的"，措辞要两边都成立 ——
                // 说"已过期"对拿到别人链接的人是假话。
                return L10n.key("That job is gone — jobs are kept for 24 hours, free files for 60 minutes.")
            case .http(409):
                return L10n.key("Not ready — the draft is still rendering, or this one was already produced.")
            case .http(413):
                return L10n.key("That file is too large — images up to 8 MB, voice samples up to 16 MB.")
            case .http(415):
                return L10n.key("That file type is not supported — images as PNG/JPEG/WebP, audio as WAV/MP3/M4A.")
            case .http(403):
                return L10n.key("That is not yours to open.")
            case .http(502), .http(504):
                return L10n.key("The provider did not answer — try again in a moment.")
            case .http(let code): return L10n.key("METAG request failed.") + " (\(code))"
            case .rejected(_, let reason):
                switch reason {
                case "inflight_limit":
                    return L10n.key("You already have two films rendering — wait for one to finish")
                case "queue_full":
                    return L10n.key("Everyone is generating right now — try again in a few minutes")
                case "insufficient_credits":
                    return L10n.key("Not enough credits.")
                case "engine_degraded":
                    return L10n.key("That engine is temporarily unavailable — pick another")
                // 频控此前一律回裸 429，于是这几种都落到下面那句"稍后再试" ——
                // 而它们是**用户自己的配额**，不是我们忙。把用户的正常状态说成
                // 我们坏了，他会以为产品有问题，而不是知道歇一会儿。
                // 并发和配额是两件事：前者"等一条跑完就行"，后者"这一小时别再来了"。
                case "sample_used":
                    return L10n.key("You've already used your free preview shot.")
                case "sample_engine":
                    return L10n.key("Pick a premium tier to preview — the built-in one is always free.")
                case "draft_not_ready":
                    return L10n.key("The draft is still rendering — wait a moment.")
                case "draft_inflight":
                    return L10n.key("You already have a few drafts running — one will free up in a moment.")
                case "draft_quota":
                    return L10n.key("You've made a lot of drafts this hour — take a break and come back shortly.")
                case "generate_quota":
                    return L10n.key("You've produced a lot this hour — take a break and come back shortly.")
                case "voice_quota", "upload_quota":
                    return L10n.key("Too many requests this hour — try again later.")
                case "tts_quota", "highlight_quota", "plan_quota":
                    return L10n.key("Too many requests this minute — try again in a moment.")
                default:
                    return L10n.key("Temporarily unavailable — try again shortly")
                }
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

    /// 204 之类没有响应体的请求。`send<T: Decodable>` 会试着解 JSON，
    /// 对空 body 必然失败 —— 那会让一次成功的删除看起来像失败。
    @discardableResult
    private static func sendNoContent(_ req: URLRequest) async throws -> Int {
        let (_, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw Failure.http(code) }
        return code
    }

    /// 只有幂等方法能自动重试。POST 可能已经在服务端生效了，重试会变成第二次下单。
    private static let retryableMethods: Set<String> = ["GET", "HEAD"]

    /// 发一个请求。**带重试。**
    ///
    /// 起因：服务器在美国弗吉尼亚，用户在中国。实测这条链路 RTT 230ms、
    /// 丢包 6.7%–20%、一次普通 API 调用 1.0–2.7 秒。零重试意味着
    /// **一次网络抖动就是用户眼里的一次报错** —— 而那类错误根本到不了
    /// 我们的服务器，任何日志里都没有。
    ///
    /// 只重试"没拿到答案"的情况：网络层错误与 5xx。
    /// 服务端已经答过的（401/402/4xx）不重试 —— 重试只会拿到同一个答案，
    /// 还会把一次"额度不足"变成连续三次。
    static func send<T: Decodable>(_ req: URLRequest, as: T.Type) async throws -> T {
        let canRetry = retryableMethods.contains(req.httpMethod?.uppercased() ?? "GET")
        let attempts = canRetry ? 3 : 1
        var lastError: Error = Failure.http(0)

        for attempt in 0..<attempts {
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                switch code {
                case 200..<300: return try JSONDecoder().decode(T.self, from: data)
                case 401:
                    token = nil
                    throw Failure.signedOut
                case 402: throw Failure.insufficientCredits
                case 429, 503:
                    // 原因码在响应体里。解不出来就退回通用文案 ——
                    // 但**绝不退回裸状态码**，那对用户毫无意义。
                    let reason = (try? JSONDecoder().decode([String: String].self, from: data))?["reason"] ?? ""
                    if code == 503 && reason.isEmpty { lastError = Failure.http(code); if attempt == attempts - 1 { throw lastError } }
                    else { throw Failure.rejected(code, reason) }
                case 502, 504:
                    lastError = Failure.http(code)
                    if attempt == attempts - 1 { throw lastError }
                default: throw Failure.http(code)
                }
            } catch let e as Failure {
                // 服务端给过答案的直接抛；只有 5xx 走到这里且还有重试机会时继续
                if case .http(let c) = e, (502...504).contains(c), attempt < attempts - 1 {
                    lastError = e
                } else {
                    throw e
                }
            } catch {
                // 网络层错误（超时、连接中断、丢包导致的失败）
                lastError = error
                if attempt == attempts - 1 { throw error }
            }
            // 退避：200ms、600ms。**丢包往往成串**，立刻重试大概率再丢一次。
            try? await Task.sleep(for: .milliseconds(200 * Int(pow(3.0, Double(attempt)))))
        }
        throw lastError
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

    /// 删掉一条作品。**用户对失败作品最基本的诉求就是让它消失** ——
    /// 一屏永远擦不掉的失败记录，是"这产品不靠谱"最直接的证据，
    /// 而且每次打开都要再看一遍。
    ///
    /// 服务端会一并清掉对象存储里的产物与索引。**额度不退**：
    /// 失败时已经退过一次，删除不该变成第二次退款。
    static func deleteFilm(_ jobId: String) async throws {
        _ = try await sendNoContent(request("api/v1/jobs/\(jobId)", method: "DELETE"))
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

    /// `narrator` 是**整片级**的修改：只重合成旁白，画面一帧不动。
    /// 只换音色时 `edits` 可以为空。
    /// 免费试渲一镜：**让用户在掏钱之前看见他要买的那个东西。**
    ///
    /// 草案是静帧 + 旁白 —— 它回答"故事对不对"，回答不了"动起来好不好看"，
    /// 而运动正是他付钱买的那件事。加上 20 credits 的赠额买不起任何付费档一镜，
    /// 新用户的全部体验都是我们最弱的一档。
    ///
    /// 一人一次，对用户 0 credits。第二次网关回 402 / sample_used。
    static func sampleShot(id: String, engine: String) async throws {
        struct Response: Decodable { let cost: Int }
        let req = try request("api/v1/preview/\(id)/sample", method: "POST",
                              body: ["engine": engine])
        _ = try await send(req, as: Response.self)
    }

    static func revisePreview(id: String, edits: [ReviseEdit] = [], narrator: MetagNarrator? = nil) async throws {
        struct Ack: Decodable { let status: String? }
        // 键名是 **shots**，不是 edits —— 网关按 shots 解析，发 edits 会拿到 400
        // 且不带任何说明。这条路此前在 Mac 上从来没成功过。
        var obj: [String: Any] = [:]
        if !edits.isEmpty {
            let data = try JSONEncoder().encode(edits)
            obj["shots"] = try JSONSerialization.jsonObject(with: data)
        }
        if let narrator { obj["narrator"] = narrator.rawValue }
        guard !obj.isEmpty else { return }   // 什么都不改就别发，网关会 400
        _ = try await send(request("api/v1/preview/\(id)/revise", method: "POST", body: obj), as: Ack.self)
    }

    /// 成片事件。**只报"发生了什么"，不报内容。**
    ///
    /// 起因：我们对导出这件事完全没有可见性 —— 片子做出来之后发生了什么，
    /// 一无所知。而那正是"产品有没有交付价值"的唯一答案：做出来了却没人导出，
    /// 等于没交付。Web 端已经在报，Mac 不报的话这个数是残的。
    ///
    /// 没登录就什么都不发；失败静默 —— 用户已经拿到文件了，
    /// 不该因为一条统计没记上而看到报错。
    static func filmEvent(kind: String, shots: Int, seconds: Double, metag: Bool) {
        Task {
            guard isSignedIn else { return }
            _ = try? await send(
                request("api/v1/films/event", method: "POST",
                        body: ["kind": kind, "shots": shots,
                               "seconds": seconds, "metag": metag]),
                as: Ack.self)
        }
    }

    private struct Ack: Decodable { let ok: Bool? }

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
    /// **逐镜时长不由客户端发。** `storyboard.shots[].seconds` 确实生效
    /// （worker 的 `_shot_seconds` 读它，Veo 就近取 4/6/8），但写它的是服务端的导演，
    /// 不是客户端；web 端的 `GenerateBody.storyboard` 里也只有这两个数组。
    /// 配方里的 `seconds` 两端都注明只作参考 —— 重生成的长度由引擎决定。
    /// 单方面从这里发出去只会让两个客户端各说各话。
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

    /// 一句话改图。返回的 frame_id 可以直接当图生视频的首帧。
    ///
    /// `frameId` 必须是 uploadFrame 回的那个，且属于本人 —— 网关会校验。
    /// 指令上限 500 字，超了 400。
    static func editImage(frameId: String, instruction: String) async throws -> (frameId: String, cost: Int) {
        struct Response: Decodable { let frame_id: String; let cost: Int }
        let req = try request("api/v1/image/edit", method: "POST",
                              body: ["frame_id": frameId, "instruction": instruction])
        let r = try await send(req, as: Response.self)
        return (r.frame_id, r.cost)
    }

    /// 取回一张上传/改过的图。
    ///
    /// 改图只回一个 frame_id，没有这条路由的话用户**看不见自己花钱改出来的东西** ——
    /// 只能生成之后才知道改成了什么样。为此在网关加了 GET /api/v1/frames/{id}。
    static func frame(_ frameId: String, to directory: URL) async throws -> URL {
        guard let token else { throw Failure.signedOut }
        var req = URLRequest(url: baseURL.appendingPathComponent("api/v1/frames/\(frameId)"))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw Failure.http(code) }
        // frame_id 自带扩展名（{uuid}.png），直接拿来当文件名
        let url = directory.appendingPathComponent(frameId)
        try data.write(to: url)
        return url
    }

    /// 把某一镜的某个候选定为交付版本。
    ///
    /// 重拍本来就会生成 N 个候选（用户为它们付了钱），而此前 Mac 端**自动采用最后
    /// 一个** —— 挑选权从来没交到用户手里。候选数据一直在 job.alts 里躺着。
    static func promoteTake(job id: String, shot: Int, file: String) async throws {
        let req = try request("api/v1/jobs/\(id)/takes/promote", method: "POST",
                              body: ["shot": shot, "file": file])
        // 返回体我们不看：成功与否已经由状态码回答了。
        struct Ignored: Decodable {}
        _ = try await send(req, as: Ignored.self)
    }

    /// 找亮点：把**文字和能量曲线**发上去，素材本身不出设备。
    ///
    /// 转写在本机做（端侧 ASR），能量曲线也在本机算（AudioEnvelope），
    /// 出设备的只有一份摘要 —— 这是我们能做而云端剪辑工具做不到的事，
    /// 别为了省事把音视频传上去。
    static func highlights(
        transcript: String, energy: [Float], duration: Double, preferences: String
    ) async throws -> [Highlight] {
        struct Response: Decodable { let highlights: [Highlight] }
        let req = try request("api/v1/highlights", method: "POST", body: [
            "transcript": transcript,
            // 能量曲线抽稀到 200 点：网关只拿它判断"哪里有劲"，
            // 逐帧发过去只是把一条跨太平洋的请求变慢。
            "energy": downsample(energy, to: 200).map { Double(($0 * 100).rounded()) / 100 },
            "duration": duration,
            "preferences": preferences,
        ])
        return try await send(req, as: Response.self).highlights
    }

    struct Highlight: Decodable, Sendable, Identifiable {
        let start: Double
        let end: Double
        let score: Double
        let title: String
        let reason: String
        var id: String { "\(start)-\(end)" }
    }

    /// 等距抽稀。`count` 不小于原长时原样返回。
    static func downsample(_ values: [Float], to count: Int) -> [Float] {
        guard count > 0, values.count > count else { return values }
        return (0..<count).map { values[$0 * values.count / count] }
    }

    /// 音频字节该存成什么扩展名。
    ///
    /// **扩展名要跟着实际内容走。** 拿 WAV 当 .mp3 存，AVFoundation 会拒绝它，
    /// 而用户看到的是"配音失败" —— 与真正的失败无从区分，也就无从排查。
    /// 认不出来时按 mp3：网关的 TTS 只会回这两种。
    static func audioExtension(for data: Data) -> String {
        data.starts(with: Array("RIFF".utf8)) ? "wav" : "mp3"
    }

    // MARK: - 声音复刻
    //
    // 音色属人身权：网关要求 consent 必须为 true，否则一律 403，并会记下来源 IP。
    // 界面上那个勾**不许预勾选**，也不许由"继续"隐含 —— 它是授权，不是偏好。

    struct Voice: Decodable, Sendable, Identifiable, Hashable {
        let id: String
        let name: String
        /// 实扣金额。**只有 /voice/clone 会回**（列表接口没有）。
        /// 对用户宣称扣了多少，一律用它，不要拿本地单价重算：
        /// 复刻失败不扣费，只有成功那次才有这个数。
        var cost: Int? = nil
    }

    static func voices() async throws -> [Voice] {
        struct Response: Decodable { let voices: [Voice] }
        return try await send(request("api/v1/voices"), as: Response.self).voices
    }

    /// 样本传对象存储，拿到语音服务商能拉到的地址。
    /// 网关只认 WAV / MP3 / M4A 的魔数，上限 16 MB，每小时 20 次。
    static func uploadVoiceSample(_ fileURL: URL) async throws -> String {
        struct Response: Decodable { let sample_url: String }
        guard let token else { throw Failure.signedOut }
        let data = try Data(contentsOf: fileURL)
        var req = URLRequest(url: baseURL.appendingPathComponent("api/v1/upload/voice-sample"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = data
        return try await send(req, as: Response.self).sample_url
    }

    static func cloneVoice(sampleURL: String, name: String) async throws -> Voice {
        let req = try request("api/v1/voice/clone", method: "POST",
                              body: ["sample_url": sampleURL, "name": name, "consent": true])
        return try await send(req, as: Voice.self)
    }

    /// 本地记录与平台侧一起删 —— 人身权数据不该留在别人服务器上。
    static func deleteVoice(_ id: String) async throws {
        try await sendNoContent(request("api/v1/voices/\(id)", method: "DELETE"))
    }

    /// 用某个音色把一段文字合成语音，落到 `directory`，返回本地文件。
    ///
    /// `voiceId` 为 nil 时走本地免费合成；给了就是云端 + 按字数计费。
    /// **响应体是音频字节，不是 JSON** —— 不能走 send<T: Decodable>。
    static func speak(text: String, voiceId: String?, to directory: URL) async throws -> URL {
        var body: [String: Any] = ["text": text]
        if let voiceId { body["voice_id"] = voiceId }
        let req = try request("api/v1/tts", method: "POST", body: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200..<300: break
        case 401: token = nil; throw Failure.signedOut
        case 402: throw Failure.insufficientCredits
        default: throw Failure.http(code)
        }
        let url = directory
            .appendingPathComponent("metag-voice-\(UUID().uuidString).\(audioExtension(for: data))")
        try data.write(to: url)
        return url
    }

    /// 轮询至终态。取消由调用方通过 Task 取消传递。
    /// 下载镜头文件到临时目录，返回本地 URL。`name` 为 shots[i].video/audio。
    static func download(job id: String, name: String, to directory: URL) async throws -> URL {
        // 绝对 URL 说明结果已落 S3（付费档），直接取；否则走网关流式端点
        let url: URL
        if let absolute = URL(string: name), absolute.scheme != nil {
            url = absolute
        } else {
            // **用票据，不要把 JWT 放进 URL。**
            //
            // 查询串会进浏览器历史、Referer、以及任何一天有人打开访问日志时的日志文件。
            // 而我们的 JWT 是 7 天有效、全端点权限 —— 泄漏一次等于账号被接管。
            // 票据只活 300 秒、只绑这一个任务：泄漏的代价从"整个账号七天"
            // 降到"一个任务五分钟"。
            //
            // web 端早就在用票据了（fileUrl），只有这里还在发完整 JWT。
            // 取不到票据时退回 token：宁可下载得到，也不要因为鉴权升级而变得取不到片子。
            let query: URLQueryItem
            if let ticket = try? await fileTicket(job: id) {
                query = URLQueryItem(name: "ticket", value: ticket)
            } else {
                guard let token else { throw Failure.signedOut }
                query = URLQueryItem(name: "token", value: token)
            }
            url = baseURL.appendingPathComponent("files/\(id)/\(name)")
                .appending(queryItems: [query])
        }
        // **下载也要重试。** API 调用早就有重试了（这条链路实测丢包 6.7%–20%），
        // 而下载的文件比一次 API 响应大两个数量级 —— 中途断掉的概率高得多，
        // 却一直是裸调用。它的调用方大多写 `try?`，于是一次网络抖动
        // **静默变成"少了一镜"**，用户看到的是一部缺画面的片子。
        //
        // 下载是幂等的（GET 同一个文件），重试没有副作用 ——
        // 这一点和 POST 不同，那边只重试"没拿到答案"的情况。
        var lastError: Error = Failure.http(0)
        for attempt in 0..<3 {
            do {
                let (temp, response) = try await URLSession.shared.download(from: url)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                // 4xx 不重试：服务端已经答过了，重试只会拿到同一个答案。
                if (400..<500).contains(code) { throw Failure.http(code) }
                guard (200..<300).contains(code) else { throw Failure.http(code) }
                let destination = directory.appendingPathComponent("\(UUID().uuidString)-\(name)")
                try FileManager.default.moveItem(at: temp, to: destination)
                return destination
            } catch let e as Failure {
                if case .http(let c) = e, (400..<500).contains(c) { throw e }
                lastError = e
            } catch {
                lastError = error
            }
            if attempt < 2 {
                // 丢包成串：立刻重试大概率再丢一次
                try? await Task.sleep(for: .seconds(pow(2.0, Double(attempt))))
            }
        }
        throw lastError
    }
}
