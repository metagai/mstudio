import Foundation

/// 手上这张票说明了什么。**纯解析，不碰钥匙串、不发网络。**
///
/// 从 `MetagGateway` 里搬出来的：它们不是网关调用，是对 JWT 的判断 ——
/// 「每个网关方法都要有调用方」那条守卫正是这么告诉我的。
///
/// 只解 payload，**不验签**：这里不是安全边界，真正的判定在网关
/// （`anon::gate` / `auth`）。客户端解它只是为了知道该给用户看什么。
enum MetagTicket {
    /// 票里的字段。只解 payload、不验签 —— **这里不是安全边界**，
/// 真正的判定在网关；客户端解它只是为了知道该给用户看什么。
static func claims(in token: String?) -> [String: Any]? {
    guard let token else { return nil }
    let parts = token.split(separator: ".")
    guard parts.count == 3 else { return nil }
    var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    while b64.count % 4 != 0 { b64 += "=" }
    guard let data = Data(base64Encoded: b64) else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

// 下面四个都拆成「纯函数 + 读钥匙串的薄壳」。判断逻辑不碰全局状态，
// 测试就不必往钥匙串里写东西 —— 并行跑的测试共用一个钥匙串必然互相踩。
static func isAnonymous(_ token: String?) -> Bool {
    (claims(in: token)?["sub"] as? String)?.hasPrefix("anon:") == true
}
static func expiry(of token: String?) -> Date? {
    (claims(in: token)?["exp"] as? Double).map { Date(timeIntervalSince1970: $0) }
}
static func isExpired(_ token: String?) -> Bool {
    guard let exp = expiry(of: token) else { return false }
    return exp <= Date()
}
static func isSignedIn(_ token: String?) -> Bool {
    // **必须解得出 sub。** 只判断"不是匿名且没过期"的话，一张烂票
    // （钥匙串损坏、被截断）两条都满足，于是 app 以为用户登录着，
    // 而每一次请求都 401 —— 用户看到的是"请登录"，点了又跳回来。
    guard let sub = claims(in: token)?["sub"] as? String, !sub.isEmpty else { return false }
    return !sub.hasPrefix("anon:") && !isExpired(token)
}
}
