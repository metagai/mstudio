import Foundation
import Testing
@testable import PalmierPro

@Suite("班底")
struct MetagCrewTests {
    /// 阶段名是**跨仓库契约**：Swift 这边写错一个字母，那个人就永远不会亮，
    /// 而界面上什么都不会报错 —— 他只是一直暗着。这条对着网关源码比。
    @Test func stageNamesMatchTheGateway() throws {
        // 只在 metag 单仓检出里跑得到（mac 也可以单独 clone，那时够不到网关源码）。
        // 够不到就直说并跳过 —— 一条悄悄变绿的守卫比没有守卫更糟。
        let worker = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Metag
            .deletingLastPathComponent()   // PalmierProTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // mac
            .deletingLastPathComponent()   // metag
            .appendingPathComponent("workers/cpu_worker.py")
        guard FileManager.default.fileExists(atPath: worker.path) else {
            print("跳过：够不到 \(worker.path)，这条只在 metag 单仓检出里有效")
            return
        }
        let src = try String(contentsOf: worker, encoding: .utf8)
        for stage in MetagCrew.stageOrder {
            #expect(src.contains("\"\(stage)\""), "网关不报 \(stage) 这个阶段，挂在它上面的人永远不会亮")
        }
    }

    /// **`review` 不能进这张表。** 草案不跑 review（导演回看是交付后台跑的），
    /// 把人挂在它上面，用户会看到一个全程暗着、从不干活的角色。
    @Test func reviewIsNotAStage() {
        #expect(!MetagCrew.stageOrder.contains("review"))
        #expect(!MetagCrew.members.contains { $0.stage == "review" })
    }

    @Test func everyMemberOwnsExactlyOneRealStage() {
        #expect(MetagCrew.members.map(\.stage) == MetagCrew.stageOrder)
        #expect(Set(MetagCrew.members.map(\.name)).count == MetagCrew.members.count)
    }

    /// 状态只由阶段决定：之前的交了活、当前的在干、后面的还没轮到。
    @Test(arguments: Array(MetagCrew.stageOrder.enumerated()))
    func standingFollowsTheStage(now: (offset: Int, element: String)) {
        for (i, member) in MetagCrew.members.enumerated() {
            let expected: MetagCrew.Standing =
                i < now.offset ? .done : (i == now.offset ? .working : .waiting)
            #expect(MetagCrew.standing(of: member, stage: now.element) == expected)
        }
        #expect(MetagCrew.current(stage: now.element)?.stage == now.element)
    }

    /// 阶段还没上来时**一个人都不亮**。宁可一个都不亮，也不要亮一个其实没在干活的。
    @Test(arguments: [nil, "", "review", "queued", "不认识的阶段"])
    func unknownStageLightsNobody(stage: String?) {
        #expect(MetagCrew.current(stage: stage) == nil)
        #expect(MetagCrew.members.allSatisfy { MetagCrew.standing(of: $0, stage: stage) == .waiting })
    }

    /// **不许有定时器。** 到场是仪式（只演一次），谁亮起来一律由阶段说了算 ——
    /// 一个按秒推进的班底，等片子卡住时还在欢快前进，那一刻仪式就穿帮了。
    /// 这条盯的是源码：`Timer` / `asyncAfter` / 带 `repeatForever` 的动画都不该出现。
    @Test func nothingAdvancesOnTime() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PalmierPro/Metag")
        for name in ["MetagCrew.swift", "MetagCrewView.swift"] {
            let src = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            for banned in ["Timer.", "asyncAfter", "repeatForever", "Task.sleep"] {
                #expect(!src.contains(banned), "\(name) 里出现了 \(banned) —— 班底的推进必须只由阶段决定")
            }
        }
    }
}
