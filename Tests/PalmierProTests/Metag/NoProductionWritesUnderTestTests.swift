import Foundation
import Testing
@testable import PalmierPro

/// **判据不许在生产上建任务。**
///
/// ## 之前发生的事（2026-09-06）
///
/// 网关那侧新加的来源列，几小时内就把一个我们查了一整天的谜团解开了：
/// 14 天里 459 个匿名账号起过草案，而漏斗只记到 40 —— 我一度断言
/// 「有人在读我们的公开仓库调接口」。**答案是我们自己。**
///
///     jobs.client = 'mac/dev'   4 条，全是匿名 preview
///     提示词全是                「一个女孩在天台上看城市的灯一格一格亮起来」
///     那句话只存在于             ViewSnapshots.swift 的夹具里
///
/// 链路：快照测试渲染 `MetagDraftSheet(initialPrompt:)`
/// → `seedIfNeeded()`（注释原话：「带着首屏那句话进来的话，**填好并立刻开跑**」）
/// → `model.draft()` → `MetagGateway.preview()` → **生产上真建一条任务**。
///
/// ## 这条线两个月前就画过一次
///
/// `MetagFunnel.isRunningTests` 的注释里写着：
/// 「打个 `probe` 标只能让报表滤掉它，**而它仍然在往生产库里写**。
/// 判据不该有副作用落在生产上，这是比数字变脏更早的一条线。」
///
/// **理由是通用的，实现是单点的** —— 当时只画在埋点上。两个月后同一条线在
/// 隔壁被踩穿，而且更贵：第一次只是数字脏了，**这次真在生产上建任务、跑 LLM、花钱**。
///
/// 所以这次画在网关这一层，**不指望每个测试作者记得** ——
/// 靠人记的规矩，这两天已经验证过三次活不过两周。
@Suite("判据不许打生产")
struct NoProductionWritesUnderTestTests {

    /// **先证明我们真的在测试环境里。**
    ///
    /// 不先断这一条的话，下面那条会在 `isRunningTests` 恒假时"通过" ——
    /// 而那正是这个仓栽过最多次的形状：**断言对不存在成立。**
    @Test func weReallyAreRunningUnderTest() {
        #expect(MetagFunnel.isRunningTests,
                "判据识别失效了 —— 下面那条会变成恒真，而生产上会重新开始多任务")
    }

    /// 写路径必须抛。
    @Test func theGatewayRefusesEveryWritePath() {
        for what in ["preview", "sampleShot", "revisePreview", "approvePreview",
                     "reshoot", "uploadFrame", "uploadVoiceSample"] {
            #expect(throws: MetagGateway.Failure.self, "\(what) 没有被拦住") {
                try MetagGateway.refuseUnderTest(what)
            }
        }
    }

    /// 抛出来的话要说得出**是哪一条路**，否则出事时看不出该改哪个测试。
    @Test func theRefusalNamesTheCallItRefused() {
        let e = MetagGateway.Failure.runningUnderTest("preview")
        let text = e.errorDescription ?? ""
        #expect(text.contains("preview"), "拒绝信息里没有点名那条路：\(text)")
        #expect(text.contains("METAG_BASE_URL"), "没告诉人下一步该怎么办：\(text)")
    }
}
