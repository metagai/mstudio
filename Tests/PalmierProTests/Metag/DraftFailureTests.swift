import Foundation
import Testing
@testable import PalmierPro

/// **等了四分钟，然后屏幕告诉他"还在拍"。**
///
/// 草案失败时 `poll` 原来直接 `return` —— 什么都不设。而 `ready` 要求
/// `status == "done"`，于是界面落回**等待**那一支：班底继续"在干活"，
/// 场记板一格不填，**永远**。
///
/// A0 只允许改"那条路上会说假话的地方" —— 这就是其中最直白的一处：
/// 不是没有出路，是产品在说假话。而中位等待就是 4 分钟（A0d 从生产库量的），
/// 十个陌生人里撞上一个，那个人会被记成"他不想留"。
@Suite("草案失败")
@MainActor
struct DraftFailureTests {
    private static func source() -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PalmierPro/Metag/MetagDraftSheet.swift")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// 失败那一支必须**先说话**，再返回。
    @Test func aFailedDraftSaysSomething() throws {
        let src = Self.source()
        let branch = try #require(src.range(of: #"if j.status == "failed" {"#))
        let tail = String(src[branch.lowerBound...].prefix(600))
        #expect(tail.contains("note = kind.message"),
                "失败又变回静默返回了 —— 界面会一直显示班底在干活")
        #expect(tail.contains("MetagFunnel.track(.filmFailed"),
                "失败没进漏斗 —— 完成率的分母又缺了一块")
    }

    /// **三种失败要说的话完全相反**，不许共用一句。
    ///
    /// 对着一次上游 503 说「换个说法」，他会去改一句根本没问题的话、
    /// 改完再失败一次 —— 我们把自己的故障算在了他头上。
    @Test func theThreeKindsSayDifferentThings() {
        let said = MetagFailureKind.allCases.map { $0.message(refunded: true) }
        #expect(Set(said).count == MetagFailureKind.allCases.count,
                "有两种失败在说同一句话")
    }

    /// **关于钱，宁可说"我在查"，绝不能说错。**
    /// 网关没说退没退（nil）时也不许说"钱回来了"。
    @Test(arguments: [nil, false] as [Bool?])
    func moneyIsNeverClaimedWithoutProof(refunded: Bool?) {
        for kind in MetagFailureKind.allCases {
            let said = kind.message(refunded: refunded)
            #expect(!said.contains("back in your balance") && !said.contains("已经退回"),
                    "\(kind.rawValue) 在没有凭据的时候说了钱已经退回")
        }
    }

    /// 拿不准的种类一律 `unknown` —— 不猜。
    @Test(arguments: [nil, "", "something_new", "UPSTREAM"])
    func unrecognisedKindsFallBackToUnknown(raw: String?) {
        #expect(MetagFailureKind(raw) == .unknown)
    }
}
