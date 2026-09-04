import Testing
@testable import PalmierPro

/// **在 METAG 里，片子在你看它的时候就活了。**
///
/// 一个手势，贯穿全产品：首屏那三条样片、「我的作品」那面墙、首映。
/// 鼠标停上去，画面自己动起来 —— 不用点、不用等、不用注册。
///
/// 这一排原来要**点一下**才动。而它是他打开 METAG 看到的第一样东西：
/// 一个视频产品，第一屏应该在他还没决定要不要试之前就先动给他看。
@Suite("停上去就活了")
struct HoverToLifeTests {
    /// **大播放器开着的时候不抢它。** 他已经在认真看一条了，
    /// 这时候旁边那张跟着动起来是打扰，不是惊喜。
    @Test func aFullPlayerIsNeverInterrupted() {
        #expect(!MetagShowcaseStrip.shouldPreview(alreadyPlaying: true, alreadyPreviewing: false),
                "他正在看大画面，旁边那张还抢着动 —— 那是打扰")
    }

    /// 同一张已经在试播，别再起一个播放器。
    @Test func oneTileNeverStartsTwice() {
        #expect(!MetagShowcaseStrip.shouldPreview(alreadyPlaying: false, alreadyPreviewing: true))
    }

    /// 安静的时候停上去，就该动。
    @Test func hoveringAQuietTileStartsIt() {
        #expect(MetagShowcaseStrip.shouldPreview(alreadyPlaying: false, alreadyPreviewing: false))
    }
}
