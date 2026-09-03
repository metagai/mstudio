import Testing
@testable import PalmierPro

/// **不在白名单里的属性会被静默丢掉。**
///
/// 隐私上这是有意的（宁可漏发，不可误发），但它的失败样子很坏：
/// 加了一个属性、忘了加进那张表 —— 报表上那一格永远是空的，
/// 而"空"和"没人用这个功能"长得一模一样。
@Suite("我们真发的属性活不活得下来")
struct AnalyticsPropertiesTests {
    /// 他是从哪儿启动的。这一格回答的是「多少人其实没装好」。
    @Test func theInstallLocationSurvives() {
        let out = Analytics.allowedProperties(
            for: Analytics.Event.appOpened.rawValue, properties: ["install": "diskImage"])
        #expect(out["install"] as? String == "diskImage",
                "启动位置被白名单丢掉了 —— 报表上会看不出有多少人其实没装好")
    }

    /// 白名单还得真的在挡东西 —— 不然这条判据是空绿的。
    @Test func theWhitelistStillBlocks() {
        let out = Analytics.allowedProperties(
            for: Analytics.Event.appOpened.rawValue,
            properties: ["install": "applications", "user_prompt": "他写的那句话"])
        #expect(out["user_prompt"] == nil, "白名单放行了它不认识的属性")
        #expect(out.count == 1)
    }
}
