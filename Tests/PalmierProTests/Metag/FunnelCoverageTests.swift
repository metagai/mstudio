import Foundation
import Testing
@testable import PalmierPro

/// **量不到的目标，使劲只会被误导得更远。**
///
/// 2026-09-01 创始人把团队目标定成三个数：成片完成率、成片内容质量
/// （愿不愿意导出/分享）、订阅转化。拿 Mac 的漏斗对了一遍 —— **三个里有两个
/// 当时量不到**：
///
/// - 导出完全不在漏斗里（走的是另一条 film-event 通道，合不到一张图上）
/// - 点订阅零埋点（`paid` 记的是按下出片，不是订阅）
/// - 完成率的**分母是错的**：零可用镜的失败一个字都不记
///
/// 这一组盯着那三个口子别再合上。
@Suite("目标量得到")
struct FunnelCoverageTests {
    private static func source(_ name: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PalmierPro/\(name)")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// 步骤名以**网关白名单**为准 —— 两套命名的漏斗合不到一张图上。
    @Test(arguments: [
        ("checkoutOpen", "checkout_open"),
        ("filmFailed", "film_failed"),
        ("exported", "exported"),
    ])
    func theNewStepsUseTheGatewayNames(swiftCase: String, wireName: String) {
        let step = MetagFunnel.Step.allCases.first { "\($0)" == swiftCase }
        #expect(step?.rawValue == wireName, "\(swiftCase) 的线上名字和网关白名单对不上")
    }

    /// **② 内容质量**：导出成功要进漏斗。这是唯一一个问"他愿不愿意留着它"的格子。
    @Test func exportingIsCounted() {
        let src = Self.source("Export/ExportQueue.swift")
        #expect(src.contains("MetagFunnel.track(.exported"),
                "导出又不在漏斗里了 —— 那是唯一一个直接回答'东西好不好'的数")
        #expect(src.contains("\"fmt\""), "没记格式，读不出他导的是什么")
    }

    /// **③ 订阅转化**：交给浏览器那一刻才记。
    ///
    /// 记在"我发起了跳转"上，转化率会凭空变好而钱一分没进来 ——
    /// 和把 `paid` 记在按钮被点上是同一个坑。
    @Test func checkoutIsCountedOnlyAfterItIsActuallyHandedOff() throws {
        let src = Self.source("Account/AccountService.swift")
        let guardLine = try #require(src.range(of: "guard openInBrowser(url) else { return }"))
        let track = try #require(src.range(of: "MetagFunnel.track(.checkoutOpen"))
        #expect(guardLine.lowerBound < track.lowerBound,
                "还没交出去就记上了 —— 拒绝打开的那次也会被算成一次转化")
        // 没标 handoff —— Mac 只知道自己交出去了，不知道 Stripe 那页有没有打开。
        // 两种含义压进同一个数字而不留痕迹，读数的人会把它当成 web 那一档。
        #expect(src.contains("\"handoff\": true"))
    }

    /// **① 完成率的分母**：零可用镜的失败必须被记下来。
    @Test func aFilmWithNoUsableShotsIsCountedAsAFailure() throws {
        let src = Self.source("Metag/MetagJobOpener.swift")
        let track = try #require(src.range(of: "MetagFunnel.track(.filmFailed"))
        let toast = try #require(src.range(of: "This film has no usable shots."))
        #expect(track.lowerBound < toast.lowerBound,
                "又变成只弹一句提示就结束了 —— 那次尝试在漏斗里根本不存在")
    }

    /// 取件过期也是"他等完了但手上是空的"。
    @Test func expiredDownloadsAreCountedToo() {
        #expect(Self.source("Metag/MetagJobOpener.swift").contains("FailureReason.expired"))
    }

    /// `why` 只用网关认的那三种。**硬塞一个进去就是给报表编原因。**
    ///
    /// 第一版这条是去源码里抓 `"why": "…"` 的字面量 —— 而它把三元里的
    /// `job.status == "failed"` 当成了一个 why，当场误报。
    /// **判据要去解析源码，通常说明源码该长得更清楚一点** ——
    /// 所以原因现在是个类型，这条直接比类型。
    @Test func failureReasonsStayInsideTheContract() {
        #expect(Set(MetagFunnel.FailureReason.allCases.map(\.rawValue))
                == ["no_shots", "render_failed", "expired"],
                "编出来的原因比不记更糟 —— 网关只认这三种")
    }
}
