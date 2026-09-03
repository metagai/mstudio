import Foundation
import Testing
@testable import PalmierPro

/// **网关会回的每一种，都得有自己的话。**
///
/// 上一版这里有两个永远走不到的分支（`Failure.http(402)` / `http(429)`）——
/// `send()` 从不抛它们，402 被翻成 `.insufficientCredits`，
/// 429 被翻成 `.rejected(429, _)`。两句话一次都没出现过，
/// 而真实的 402、429、409、403 全掉进「重拍起不来」那一句。
/// **对 402 来说那句话是错的**：它起得来，他订阅一下就行。
///
/// 判据从前照着死分支写，跟着一起绿 —— 这是「判据覆盖的那条路，
/// 和用户走的那条路不是同一条」的又一次。
@Suite("重拍没起来时说哪一句")
@MainActor
struct ReshootFailureTests {
    /// `reshoot_core` 会回的五种，加上根本没走到服务端那一种。
    private static let real: [(name: String, error: Error)] = [
        ("402 没订阅 / 付费引擎", MetagGateway.Failure.insufficientCredits),
        ("429 自研引擎小时配额", MetagGateway.Failure.rejected(429, "")),
        ("409 片子没出完 / 这一镜已在重拍", MetagGateway.Failure.http(409)),
        ("403 不是这个账号的片子", MetagGateway.Failure.http(403)),
        ("断网 / 超时", MetagGateway.Failure.offline(.timedOut)),
    ]

    @Test func everyRealFailureSaysSomethingOfItsOwn() {
        let generic = MetagReshoot.message(for: MetagGateway.Failure.http(500))
        for (name, error) in Self.real {
            let m = MetagReshoot.message(for: error)
            #expect(m != generic,
                    "\(name) 掉进了通用那一句「\(generic)」—— 他不知道该干什么")
            #expect(!m.isEmpty)
        }
    }

    /// 五句话互不相同 —— 分档不是把五种情况合成一句。
    @Test func theyDoNotCollapseIntoOne() {
        let all = Self.real.map { MetagReshoot.message(for: $0.error) }
        #expect(Set(all).count == all.count, "几种失败共用了同一句话")
    }

    /// 认不出来的错还是要有一句兜底，不许是空的。
    @Test func anUnknownFailureStillSaysSomething() {
        #expect(!MetagReshoot.message(for: MetagGateway.Failure.http(500)).isEmpty)
    }
}
