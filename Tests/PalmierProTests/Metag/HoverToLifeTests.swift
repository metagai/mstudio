import Foundation
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
    private static let film = MetagShowcase(
        id: "second-take", line: "第一遍不对，就再来一遍。",
        poster: URL(string: "https://metag.ai/media/p.jpg")!,
        reel: URL(string: "https://metag.ai/media/r.mp4")!, aspect: 16.0 / 9)

    /// **移开就全清干净。** 播放器、定时器、观察者，一样都不许留下 ——
    /// 一个"多半会被清掉"的资源和一个泄漏的资源，在开发机上长得一模一样，
    /// 而它在用户那儿的样子是风扇转起来、电池掉得快。
    @Test @MainActor func nothingIsLeftBehindWhenHeMovesOn() async throws {
        let preview = ShowcasePreview()

        // **先让播放器真的建出来。**
        //
        // 第一版这条是空的：`begin` 排的是一个 180ms 之后才建播放器的任务，
        // 而我在同一个循环里立刻 `end` —— **循环里根本没有播放器被建出来**，
        // 断言"空"永远成立。把清理改坏（只暂停、不摘掉）它照样绿。
        //
        // 判据要能红，被测的那件事得先真的发生。
        // **等它出现，不赌它多快出现。**
        // 固定睡 330ms 那一版在满载并行时也红了 —— 和我刚修好的那几条同一个病。
        preview.begin(Self.film, fullPlayerOpen: false) { true }
        // **等那个任务，不等一个秒数。**
        // 上一版是 `AsyncWait.until(…)`（默认 10 秒）—— 全量并行跑时
        // 那个 180ms 的主 actor 任务能被饿到十秒以上，而它红出来的样子
        // 和"清理坏了"一模一样。给句柄不给预算。
        await preview.awaitSettleForTesting(Self.film.id)
        try #require(!preview.players.isEmpty, "播放器压根没建起来 —— 这条判据什么都没测")

        preview.end(Self.film.id)
        #expect(preview.players.isEmpty, "移开之后还留着播放器")

        // 整片离开也要清干净。
        preview.begin(Self.film, fullPlayerOpen: false) { true }
        await preview.awaitSettleForTesting(Self.film.id)
        try #require(!preview.players.isEmpty, "第二次没起来")
        preview.endAll()
        #expect(preview.players.isEmpty, "离屏之后还留着播放器")
    }

    /// **路过不算看。** 180ms 之内鼠标已经走了，就不该起播放器。
    @Test @MainActor func passingByNeverStartsAPlayer() async throws {
        let preview = ShowcasePreview()
        preview.begin(Self.film, fullPlayerOpen: false) { false }   // 已经不在上面了
        try await Task.sleep(for: ShowcasePreview.settleDelay * 4)
        #expect(preview.players.isEmpty, "鼠标只是路过，却起了一个播放器")
    }

    /// **大播放器开着的时候不抢它。** 他已经在认真看一条了，
    /// 这时候旁边那张跟着动起来是打扰，不是惊喜。
    @Test func aFullPlayerIsNeverInterrupted() {
        #expect(!ShowcasePreview.shouldPreview(alreadyPlaying: true, alreadyPreviewing: false),
                "他正在看大画面，旁边那张还抢着动 —— 那是打扰")
    }

    /// 同一张已经在试播，别再起一个播放器。
    @Test func oneTileNeverStartsTwice() {
        #expect(!ShowcasePreview.shouldPreview(alreadyPlaying: false, alreadyPreviewing: true))
    }

    /// 安静的时候停上去，就该动。
    @Test func hoveringAQuietTileStartsIt() {
        #expect(ShowcasePreview.shouldPreview(alreadyPlaying: false, alreadyPreviewing: false))
    }
}
