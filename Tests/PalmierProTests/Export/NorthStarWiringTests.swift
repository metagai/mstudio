import Foundation
import Testing
@testable import PalmierPro

/// **「十个人里有几个把片子留下来」—— 这个数记得下来。**
///
/// ## 为什么这一条要存在
///
/// 2026-09-06 我把整条 Mac 线的实验押在一个数上：手招十个陌生人，
/// 看有几个把片子留下来。**押之前先问了一句"这个数真的记得下来吗"** ——
/// 因为它此前**从来没有在生产上响过一次**：
///
///     exported 全量 1075 条   probe=true   1075 条
///     真人的                              **0 条**
///
/// 当天用一发带 `probe` 标的探针验通了网关那一半（`where='keepIt'` 存得进
/// `funnel_events`）。**这一条守的是客户端那一半。**
///
/// ## 它守的那个静默失效
///
/// `where` 记的是 `ExportJobSource` 的 `rawValue`，而报表那侧是按
/// **字面量 `keepIt`** 筛的。谁把 `case keepIt` 改个名（或给它加一个显式
/// rawValue），编译过、测试全绿、埋点照发 —— 只是从此记成别的字符串。
///
/// **而我那一筛会返回 0，跟"没人想留"长得一模一样。**
/// 这正是这个仓栽过最多次的形状：一个数变成 0，而 0 没有主语。
///
/// ⚠ 所以这里**故意钉死字面量**。它红的时候要改的不止这一行 ——
/// `workers/funnel_report.py` 那一格得同时改，否则两边会静静地错开。
@Suite("留下它这一格记得下来")
struct NorthStarWiringTests {

    /// 报表那侧筛的字面量。**两边同时改，或者都不改。**
    private static let whatTheReportFiltersOn = "keepIt"

    /// 埋点发出去的那个 `where`，就是报表筛的那个字面量。
    @Test func theKeepItSourceIsTheStringTheReportLooksFor() {
        #expect(ExportJobSource.keepIt.rawValue == Self.whatTheReportFiltersOn,
                """
                「留下它」的 rawValue 变了。埋点会从此记成 \
                '\(ExportJobSource.keepIt.rawValue)'，而报表还在筛 \
                '\(Self.whatTheReportFiltersOn)' —— 那一格会变成 0，
                而 0 跟"没人想留"分不开。改的话 workers/funnel_report.py 要一起改。
                """)
    }

    /// 报文的形状：`step` 是 `exported`，`meta.where` 就是那个 rawValue。
    /// **不断这一条的话，上面那条在 `where` 被挪去别的键名之后仍然恒真。**
    @Test func theExportedEventCarriesWhereUnderMeta() throws {
        let body = MetagFunnel.body(.exported,
                                    meta: ["where": ExportJobSource.keepIt.rawValue])
        #expect(body["step"] as? String == "exported")
        let meta = try #require(body["meta"] as? [String: Any])
        #expect(meta["where"] as? String == Self.whatTheReportFiltersOn,
                "`where` 这个键名变了 —— 网关按 meta->>'where' 读，会读到 NULL")
    }

    /// 三档必须互相分得开 —— 否则"他自己配参数导的"和"他按了留下它"
    /// 会挤进同一格，而那正是这一档单列出来的全部理由。
    @Test func theThreeSourcesStayDistinct() {
        let all: [ExportJobSource] = [.manual, .agent, .keepIt]
        let names = all.map { $0.rawValue }
        #expect(Set(names).count == 3, "导出来源有重名：\(names)")
    }
}
