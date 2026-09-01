import Foundation

/// 匿名漏斗埋点。步骤名以网关白名单为准（gateway/src/funnel.rs）——
/// 两套命名的漏斗合不到一张图上。只发一个随机 id，绝不 await、绝不抛。
enum MetagFunnel {
    /// **注释不会自己过期，但它会自己变成谎。**
    ///
    /// 这里原来写着「桌面端没有 checkout_open：Mac 的内购路径还没开，
    /// 埋一条恒为零的线只会误导」。写下来那天它是对的；后来账号页和额度卡
    /// 都接上了 Stripe，而这句话留在原地，**替一个真实存在的缺口作了证** ——
    /// 和「登录可发起」为一条死路作证两个月是同一个形状。
    enum Step: String, CaseIterable {
        case landed
        case lineReady = "line_ready"
        case draftStarted = "draft_started"
        case draftSeen = "draft_seen"
        case wall
        case shared
        /// **按下出片、而且网关真的收下了。** 不是按钮被点了 ——
        /// 一次失败的批准记成 paid，会让转化率凭空变好而钱一分没进来。
        case paid
        /// 片子到他手上了。web 端用这一格把"没到手"和"到了没看"切开 ——
        /// 那两半该改的东西完全相反。
        case filmReady = "film_ready"
        case signedIn = "signed_in"
        /// 收银台交给系统浏览器了。
        ///
        /// **web 记的是"那一页真的打开了"，Mac 只能记"我把它交出去了"** ——
        /// 我们不知道 Stripe 那一页有没有加载出来。两种含义不能压进同一个数字
        /// 而不留痕迹，所以 Mac 这一格一律带 `handoff: true`，
        /// 读数的人一眼知道它比 web 松一档。
        case checkoutOpen = "checkout_open"
        /// **他等完了，但没拿到能用的东西。**
        ///
        /// 之前这件事一个字都不记：零可用镜的片子直接弹一句提示就结束了，
        /// 而漏斗里这次尝试根本不存在 —— **失败是隐形的，于是完成率算出来
        /// 比真实的好看**。分母缺了失败，成功率就不是成功率，
        /// 是"成功的人里有多少成功了"。
        ///
        /// `meta.why`：`no_shots` / `render_failed` / `expired`，三种的下一步完全不同。
        case filmFailed = "film_failed"
        /// 他把片子导出来了。**这一格是唯一一个问"他愿不愿意留着它"的** ——
        /// 其余每一格问的都是"他有没有走完流程"。
        ///
        /// `meta.where` 哪一屏、`meta.fmt` 什么格式。不记文件名、不记内容。
        /// 读数**按人去重不按次数**：一个人可能导好几次。
        case exported
    }

    /// `film_failed` 的 `why`。**只有网关认的这三种。**
    ///
    /// 做成类型而不是字符串字面量，是因为字面量散在调用点上时，
    /// 想检查"有没有人编了一个原因"就只能去解析源码 —— 而我第一版判据
    /// 正是那么写的，它把三元里的 `job.status == "failed"` 当成了一个 why。
    /// **判据要去解析源码，通常说明源码该长得更清楚一点。**
    enum FailureReason: String, CaseIterable, Sendable {
        /// 模型没画出可用的镜。
        case noShots = "no_shots"
        /// 流水线断了。
        case renderFailed = "render_failed"
        /// 取件过期 —— 他等完了，手上还是空的。
        case expired
    }

    /// 这条事件来自哪个客户端。和落地页的 `page: "landing"` 对齐。
    private static let page = "mac"

    private static let anonKey = "metag.funnel.anon"

    /// 锁和状态放在一起，别人就没法只用其中一半。
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var seen = Set<String>()
        func fresh(_ k: String) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return seen.insert(k).inserted
        }
    }
    private static let once = Once()

    private static var anon: String {
        let d = UserDefaults.standard
        if let a = d.string(forKey: anonKey), a.count >= 8 { return a }
        let a = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        d.set(a, forKey: anonKey)
        return a
    }

    /// **默认全记。** 去重只给真正一次会话只发生一次的事（打开 app、登录）。
    ///
    /// 原来默认是 `once: true`，于是 `line_ready` / `draft_started` / `draft_seen`
    /// **一次会话里只记第一条草案** —— 用户做三条，我们只看到一条，
    /// 而"他试了几次"恰恰是这几格存在的全部理由。
    /// 漏斗的安全默认是"多记"，不是"少记"：多记看得出来，少记看不出来。
    static func track(_ step: Step, once: Bool = false, meta: [String: Any]? = nil) {
        if once, !Self.once.fresh(step.rawValue) { return }
        // **每一条都带 page。** 不带的话 `meta` 整个是 NULL，而在报表里
        // 一个 NULL meta 的事件和一个裸脚本长得一模一样 —— 真实用户会被当噪音
        // 过滤掉，或者算进 web 的分母里。落地页写 "landing"，我们写 "mac"。
        //
        // 放在这里而不是各个调用点：每处各写一次，迟早有一处忘记，
        // 而忘记的后果是那一格的用户在报表里直接消失。
        var payload: [String: Any] = ["page": Self.page]
        if let meta { payload.merge(meta) { _, new in new } }
        let body: [String: Any] = ["anon": anon, "step": step.rawValue, "meta": payload]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }

        var req = URLRequest(url: MetagGateway.baseURL.appendingPathComponent("api/v1/funnel"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 没登录也照发：最上面两步发生在登录之前，要求登录就量不到最大的那一段。
        if let token = MetagGateway.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = data
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req).resume()
    }
}
