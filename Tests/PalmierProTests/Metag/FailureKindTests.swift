import Foundation
import Testing
@testable import PalmierPro

/// **三种失败要说的话完全不一样，说错一种比不说更糟。**
///
/// 网关那侧 `workers/failure.py` 的文档字符串写得很清楚：
/// 「`error` 那一句是给人看的，**种类是给界面看的** ——
/// 界面据此决定下一步那颗按钮该说什么。」
///
/// 而 Mac 从来没解过 `error_kind`，于是那个"据此决定"的界面从来没拿到依据。
/// 更糟的是 2026-09-01 上午我把这句改成了「换个说法或者换一档再试」——
/// 那是给内容判回的话，却发给了所有人：**对着一次上游 503 说这句，
/// 他会去改一句根本没问题的话、改完再失败一次，我们把自己的故障算在了他头上。**
@Suite("失败的种类")
@MainActor
struct FailureKindTests {
    @Test(arguments: [("upstream", MetagFailureKind.upstream),
                      ("moderation", .moderation),
                      ("unknown", .unknown)])
    func theGatewaysVocabularyIsHonoured(raw: String, kind: MetagFailureKind) {
        #expect(MetagFailureKind(raw) == kind)
    }

    /// **拿不准就 unknown** —— 「我们看到了」这句在任何情况下都不算撒谎。
    @Test(arguments: [nil, "", "something_new"])
    func anythingElseFallsBackToUnknown(raw: String?) {
        #expect(MetagFailureKind(raw) == .unknown)
    }

    /// 三句话必须互不相同。**共用一句就等于没有分类。**
    @Test func eachKindSaysSomethingDifferent() {
        let said = Set(MetagFailureKind.allCases.map(\.message))
        #expect(said.count == MetagFailureKind.allCases.count,
                "三种失败又共用一句话了 —— 那正是分类存在的理由")
    }

    /// **判据不许断言渲染出来的那句话。**
    ///
    /// 第一版比的是 `message` 的内容 —— 而这台机器界面是中文，
    /// 于是「内容判回要让他改」当场红（中文里没有 "different way"），
    /// 而「上游故障不许怪他写法」**因为同样的原因绿了** —— 一条假绿。
    /// 一个判据在不同语言下给不同答案，它测的就不是意图。
    ///
    /// 所以比英文原串（意图写在那儿），不比渲染结果。
    private static var copy: String {
        (try? String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/PalmierPro/Metag/MetagFailure.swift"),
            encoding: .utf8
        )) ?? ""
    }

    /// 上游故障**不许让他去改自己的话** —— 那句话没问题，
    /// 改完还是会失败，而他会以为是自己写错了。
    @Test func anOutageNeverBlamesHisWriting() throws {
        let src = Self.copy
        let upstream = try #require(src.range(of: "case .upstream:"))
        let moderation = try #require(src.range(of: "case .moderation:"))
        let line = String(src[upstream.upperBound..<moderation.lowerBound]).lowercased()
        for blame in ["change a line", "different way", "describ"] {
            #expect(!line.contains(blame), "把我们的故障说成了他的写法问题")
        }
        #expect(line.contains("try again"), "没告诉他可以再来")
    }

    /// 内容判回要让他**改**，不是让他**等**。
    @Test func moderationAsksHimToRewriteNotToWait() throws {
        let src = Self.copy
        let moderation = try #require(src.range(of: "case .moderation:"))
        let unknown = try #require(src.range(of: "case .unknown:"))
        let line = String(src[moderation.upperBound..<unknown.lowerBound]).lowercased()
        #expect(line.contains("different way") || line.contains("describ"))
        #expect(!line.contains("minutes"), "让他等一次永远不会自己好的失败")
    }

    /// 那一屏真的用了它，而不是继续发一句通用的话。
    @Test func theToastUsesTheKind() throws {
        let src = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/PalmierPro/Metag/MetagJobOpener.swift"),
            encoding: .utf8
        )
        #expect(src.contains("MetagFailureKind(job.error_kind)"),
                "又回到一句通用的失败提示了")
        #expect(src.contains("message: kind.message"))
        #expect(src.contains("\"kind\": kind.rawValue"),
                "漏斗里没记真实种类 —— 我们看不出失败是哪一类")
    }
}
