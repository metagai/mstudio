import Foundation
import Testing
@testable import PalmierPro

/// 陌生人先看一眼自己那条片子。守的是**两种最容易搞错的身份判断**：
/// 匿名票不能算登录，过期的票不能当成还能用。
@Suite("匿名先看一眼")
struct MetagAnonTests {
    /// 造一张不验签的票 —— 客户端本来就只解 payload（真正的判定在网关）。
    private static func ticket(sub: String, expiresIn: TimeInterval) -> String {
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

    /// **匿名票不算登录。** 只判断 token 在不在的话，界面会以为他能出片，
    /// 而他按下去拿一个 sign_in_required —— 先让他相信可以，再告诉他不行。
    @Test func anonymousTicketIsNotSignedIn() {
        #expect(MetagTicket.isAnonymous(Self.ticket(sub: "anon:abc123", expiresIn: 3600)))
        #expect(!MetagTicket.isSignedIn(Self.ticket(sub: "anon:abc123", expiresIn: 3600)))
    }

    @Test func realTicketIsSignedIn() {
        #expect(!MetagTicket.isAnonymous(Self.ticket(sub: "google:1234", expiresIn: 3600)))
        #expect(MetagTicket.isSignedIn(Self.ticket(sub: "google:1234", expiresIn: 3600)))
    }

    /// 过期的票留着比没有票更糟：每一次请求都 401，而界面会说成"请登录" ——
    /// 用户不知道自己其实登录过，也不知道为什么昨天还好好的。
    @Test func expiredTicketIsNotUsable() {
        #expect(MetagTicket.isExpired(Self.ticket(sub: "anon:abc123", expiresIn: -60)))
        #expect(!MetagTicket.isSignedIn(Self.ticket(sub: "anon:abc123", expiresIn: -60)))
        #expect(MetagTicket.isExpired(Self.ticket(sub: "google:1234", expiresIn: -60)), "登录用户的票过期了同样不该当成还能用")
    }

    @Test func liveTicketIsNotExpired() {
        #expect(!MetagTicket.isExpired(Self.ticket(sub: "anon:abc", expiresIn: 7 * 24 * 3600)))
        #expect(MetagTicket.expiry(of: Self.ticket(sub: "anon:abc", expiresIn: 7 * 24 * 3600)) != nil)
    }

    /// 没有票的时候两个判断都不该乱说。
    @Test func noTicketSaysNothing() {
        #expect(!MetagTicket.isSignedIn(nil))
        #expect(!MetagTicket.isAnonymous(nil))
        #expect(!MetagTicket.isExpired(nil), "没有票不等于票过期 —— 那是两种不同的处境")
    }

    /// 坏票不能让判断崩掉，也不能被当成登录。
    @Test(arguments: ["", "not-a-jwt", "a.b", "a.!!!.c"])
    func malformedTicketIsNeverSignedIn(raw: String) {
        #expect(!MetagTicket.isSignedIn(raw))
        #expect(!MetagTicket.isAnonymous(raw))
    }
}
