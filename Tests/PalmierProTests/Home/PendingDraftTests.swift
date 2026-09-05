import Foundation
import Testing
@testable import PalmierPro

/// **他打完那一句、按下去，这一份不能丢。**
///
/// `startFilm` 建完工程就 `showWindows()`，紧接着发 `.metagStartDraft`。
/// 听它的 `MediaTab` 是个 SwiftUI 视图，**它的 `.onReceive` 要等第一次渲染
/// 才订阅上** —— 窗口刚出来那一刻它订没订上，取决于当时机器多忙。
///
/// 赢了竞态一切正常；输了的样子是**他打了字、按了钮，落进一个空编辑器**。
/// 而那是我们最贵的那一次交互。
///
/// 2026-09-04 刚在引导层上修过同一个形状（那条通知一个接收者都没有），
/// 这一条是它的孪生兄弟：**有接收者，但可能还没醒。**
@Suite("那一句不能丢")
@MainActor
struct PendingDraftTests {

    /// 醒得晚也取得到。
    @Test func aPanelThatWakesLateStillGetsIt() {
        let app = AppState.shared
        _ = app.takePendingDraft()            // 清干净再开始
        app.queueDraft(prompt: "天台上的灯", assets: [])
        let got = app.takePendingDraft()
        #expect(got?.prompt == "天台上的灯")
    }

    /// **取走即清。** 一份草案只该开一张卡 ——
    /// 不清的话，他关掉面板再打开，那一句会又冒出来一次。
    @Test func itIsHandedOverExactlyOnce() {
        let app = AppState.shared
        _ = app.takePendingDraft()
        app.queueDraft(prompt: "只此一次", assets: [])
        #expect(app.takePendingDraft()?.prompt == "只此一次")
        #expect(app.takePendingDraft() == nil, "第二个面板又开了一张")
    }

    /// 图片跟着一起过去 —— 中间丢掉的话，他会以为我们没看见他贴的参考图。
    @Test func theAttachedImagesRideAlong() {
        let app = AppState.shared
        _ = app.takePendingDraft()
        let urls = [URL(fileURLWithPath: "/tmp/a.png"), URL(fileURLWithPath: "/tmp/b.png")]
        app.queueDraft(prompt: "带图", assets: urls)
        #expect(app.takePendingDraft()?.assets == urls)
    }

    /// **交接那一手要同时做两件事。**
    ///
    /// 第一版判据只测 `queueDraft` 本身 —— 把 `startFilm` 里那一行删掉，
    /// 判据照样全绿。**测的是零件，不是它有没有被装上。**
    @Test func theHandOffBothQueuesAndAnnounces() async {
        let app = AppState.shared
        _ = app.takePendingDraft()
        var heard: String?
        let token = NotificationCenter.default.addObserver(
            forName: .metagStartDraft, object: nil, queue: .main
        ) { note in heard = note.userInfo?["prompt"] as? String }
        defer { NotificationCenter.default.removeObserver(token) }

        app.handOffDraft(prompt: "两条路", assets: [])
        #expect(app.pendingDraft?.prompt == "两条路", "没排队 —— 面板醒得晚就丢了")
        await Task.yield()
        #expect(heard == "两条路", "没发通知 —— 面板已经醒着的那条路断了")
    }

    /// 没人排队的时候不要凭空开一张。
    @Test func nothingQueuedOpensNothing() {
        let app = AppState.shared
        _ = app.takePendingDraft()
        #expect(app.takePendingDraft() == nil)
    }
}
