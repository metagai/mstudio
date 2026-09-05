import Foundation
import Testing
@testable import PalmierPro

/// 票到期那一天，人还在不在线上。
///
/// 网关签 7 天的票，在最后 3 天里每次 `/me` 都随手回一张新的
/// （`gateway/src/main.rs` 的 `should_renew` / `RENEW_BEFORE_S`），
/// 那段注释写着「只要他这一周来过一次，就永远不会在动手的那一刻被踢出去」。
///
/// **那句话在 Mac 上从来没成立过** —— `Account` 里没有 `token` 这个字段，
/// 新票解码即丢。每个登录用户第 7 天必被踢一次，跟他用得多勤无关。
/// 是网关那侧的契约判据先看见的：
/// `✓ /me 带着续期用的 token 键   Mac 端目前把它丢了`。
///
/// 这里守的是**换票的判断**，纯函数，不碰钥匙串 ——
/// 并行跑的测试共用一个钥匙串，往里写东西必然互相踩。
@Suite("续期的票不能扔")
struct TicketRenewalTests {
    /// 造一张不验签的票 —— 客户端本来就只解 payload（真正的判定在网关）。
    private static func ticket(sub: String = "google:1234", expiresIn: TimeInterval) -> String {
        let payload: [String: Any] = [
            "sub": sub,
            "exp": Date().addingTimeInterval(expiresIn).timeIntervalSince1970,
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let b64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "x.\(b64).y"
    }

    /// **这一条就是那个 bug 本身。** 手上的票还剩 1 天，网关回了张 7 天的，
    /// 必须换 —— 不换的话明天他就得重新登录一次。
    @Test func adoptsAFreshTicketWhenTheOldOneIsAboutToExpire() {
        let current = Self.ticket(expiresIn: 24 * 3600)
        let fresh = Self.ticket(expiresIn: 7 * 24 * 3600)
        #expect(MetagTicket.shouldAdopt(fresh, replacing: current))
    }

    /// `/me` 的 JSON 里，`token` 这个键**必须解得进来**。
    /// 它以前不在 `Account` 上，于是网关发了、客户端扔了，两边都不报错。
    @Test func accountDecodesTheRenewalToken() throws {
        let fresh = Self.ticket(expiresIn: 7 * 24 * 3600)
        let json = """
        {"sub":"google:1234","credits":42,"subscribed":false,"sub_until":0,
         "sub_status":null,"email":null,"email_verified":false,"token":"\(fresh)"}
        """
        let account = try JSONDecoder().decode(
            MetagGateway.Account.self, from: Data(json.utf8))
        #expect(account.token == fresh, "网关发的续期票没解进来 —— 这正是原来的 bug")
    }

    /// 不续期的时候网关不回这个键。**缺键不能让整个 `/me` 解码失败** ——
    /// 那会把「余额和订阅状态」一起弄丢，比不续期严重得多。
    @Test func accountStillDecodesWhenThereIsNoRenewal() throws {
        let json = """
        {"sub":"google:1234","credits":42,"subscribed":false,"sub_until":0,
         "sub_status":null,"email":null,"email_verified":false,"token":null}
        """
        let account = try JSONDecoder().decode(
            MetagGateway.Account.self, from: Data(json.utf8))
        #expect(account.token == nil)
        #expect(account.credits == 42)
    }

    /// **烂票比不换更糟。** 一张截断的票会把人当场踢下线，
    /// 而他明明刚刚才成功调过 `/me`。
    @Test func refusesATicketItCannotRead() {
        let current = Self.ticket(expiresIn: 24 * 3600)
        for junk in ["", "not-a-jwt", "x.@@@.y"] {
            #expect(!MetagTicket.shouldAdopt(junk, replacing: current),
                    "解不开的票被换上去了：\(junk)")
        }
    }

    /// 过期的票也不许换上 —— 它满足"非空"，却会让下一次请求直接 401。
    @Test func refusesAnAlreadyExpiredTicket() {
        let current = Self.ticket(expiresIn: 24 * 3600)
        #expect(!MetagTicket.shouldAdopt(Self.ticket(expiresIn: -60), replacing: current))
    }

    /// 匿名票不许换掉登录票。`/me` 不对陌生人开放，真回来了就是出事了，
    /// 而"把登录用户降级成陌生人"是这里能犯的最贵的错。
    @Test func refusesToDowngradeASignedInTicketToAnonymous() {
        let current = Self.ticket(sub: "google:1234", expiresIn: 24 * 3600)
        let anon = Self.ticket(sub: "anon:abc123", expiresIn: 7 * 24 * 3600)
        #expect(!MetagTicket.shouldAdopt(anon, replacing: current))
    }

    /// **更早到期的票不许换上。** 重放或乱序的响应会拿一张旧票换掉好票 ——
    /// 不报错、不失败，只是把会话白白缩短。
    @Test func refusesATicketThatExpiresSoonerThanTheOneWeHold() {
        let current = Self.ticket(expiresIn: 7 * 24 * 3600)
        #expect(!MetagTicket.shouldAdopt(Self.ticket(expiresIn: 3600), replacing: current))
    }

    /// 手上没票（或票已损坏）时，一张好票直接收下 —— 总比没有强。
    @Test func adoptsWhenWeHoldNothingReadable() {
        let fresh = Self.ticket(expiresIn: 7 * 24 * 3600)
        #expect(MetagTicket.shouldAdopt(fresh, replacing: nil))
        #expect(MetagTicket.shouldAdopt(fresh, replacing: "garbage"))
    }
}
