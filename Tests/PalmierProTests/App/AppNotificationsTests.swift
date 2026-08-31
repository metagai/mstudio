import Testing
@testable import PalmierPro

/// 原来这几条写死了英文原文（还带着上游的品牌名），在中文系统上必红 ——
/// 红的不是通知文案，是测试自己依赖了开发机的系统语言。
///
/// 要守的不变量与语言无关：**每种素材类型说的是不同的一句话，数量出现在里面，
/// 而且没名字时不会出现空荡荡的引号。** 当初写它，是因为无名素材的通知长成了
/// "「」 已准备就绪"。
/// `@Test(arguments:)` 在 actor 之外求值，所以这张表不能挂在 @MainActor 的类型里。
private let notifiableClipTypes: [ClipType] = [.video, .audio, .image, .text, .lottie, .sequence]

@Suite("App notifications")
@MainActor
struct AppNotificationsTests {

    @Test func eachTypeGetsItsOwnSentence() {
        // sequence 和 video 说同一句是有意的：用户眼里它们都是"视频"。
        let bodies = Set(notifiableClipTypes.map {
            AppNotifications.generationBody(assetName: "", assetType: $0, count: 2)
        })
        #expect(bodies.count == notifiableClipTypes.count - 1)
    }

    @Test(arguments: notifiableClipTypes)
    func countedMessagesStateTheCount(type: ClipType) {
        #expect(AppNotifications.generationBody(assetName: "", assetType: type, count: 2).contains("2"))
    }

    /// 名字只有空白时不能漏出引号或占位符 —— 那是这几条测试当初存在的理由。
    @Test(arguments: notifiableClipTypes)
    func unnamedAssetsReadAsCompleteSentences(type: ClipType) {
        let body = AppNotifications.generationBody(assetName: " ", assetType: type, count: 1)
        #expect(!body.isEmpty)
        for stray in ["\"\"", "“”", "「」", "%@", "()"] {
            #expect(!body.contains(stray), "无名素材的通知漏出了 \(stray)：\(body)")
        }
    }
}
