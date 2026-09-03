import Testing
@testable import PalmierPro

/// **首映。** 他的片子落地的那一刻，屏幕上放的是片子，不是一个工程。
///
/// 在这之前：他写了一句话、等了两分钟、付了 credits，然后画面里出现的是
/// 十一个片段、三条轨、一个检查器面板，和侧边栏里一句「已载入 5 镜」。
/// **那是机器在报工，不是产品在交付**，而他不是剪辑师。
@Suite("片子落地那一刻")
@MainActor
struct PremiereTests {
    /// 抢救回来的那一版，不能说"你的片子"说得那么满。
    @Test func aSalvagedFilmDoesNotGetTheFullSentence() {
        let full = MetagPremiere.headline(shots: 5, salvaged: false)
        let saved = MetagPremiere.headline(shots: 5, salvaged: true)
        #expect(full != saved, "抢救回来的和完整出片说了同一句话")
        for line in [full, saved] {
            #expect(line.contains("5"), "没说清有几镜：\(line)")
            #expect(!line.isEmpty)
        }
    }

    /// **幕升起来的条件是"真拿到画面了"。**
    ///
    /// 一格都没到的时候没有什么可首映的 —— 那时该说的是出了什么事，
    /// 而不是请他为一片空白做决定。
    @Test func nothingToScreenMeansNoCurtain() {
        let editor = EditorViewModel()
        #expect(editor.premiere == nil, "编辑器一开始就挂着幕")
    }

    /// 三个选择互不相同，而且都不是空的 —— 这三颗决定他接下来做什么。
    @Test func theThreeChoicesAreDistinct() {
        let choices = [
            L10n.string("Keep it"), L10n.string("Again"), L10n.string("I'll edit it"),
        ]
        #expect(choices.allSatisfy { !$0.isEmpty })
        #expect(Set(choices).count == 3)
    }
}
