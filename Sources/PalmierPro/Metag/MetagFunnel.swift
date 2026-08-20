import Foundation

/// 匿名漏斗埋点。步骤名以网关白名单为准（gateway/src/funnel.rs）——
/// 两套命名的漏斗合不到一张图上。只发一个随机 id，绝不 await、绝不抛。
enum MetagFunnel {
    /// 桌面端没有 checkout_open：Mac 的内购路径还没开，埋一条恒为零的线只会误导。
    enum Step: String {
        case landed
        case lineReady = "line_ready"
        case draftStarted = "draft_started"
        case draftSeen = "draft_seen"
        case wall
        case shared
    }

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

    static func track(_ step: Step, once: Bool = true, meta: [String: Any]? = nil) {
        if once, !Self.once.fresh(step.rawValue) { return }
        var body: [String: Any] = ["anon": anon, "step": step.rawValue]
        if let meta { body["meta"] = meta }
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
