import Testing
@testable import PalmierPro

/// **"还没配好"不是"出事了"。**
///
/// 「没有可用的音乐模型」原来涂成错误红 —— 他刚打开面板、什么都没做，
/// 就看到一句红字，而红色在这个产品里只有一个意思：出事了。
/// 更糟的是它**没说下一步**：一句红色的死胡同。
///
/// 过不去分两种，要说的话正好相反：
/// **「你做错了」要红并说清哪里错；「还没配好」要平静并给一扇门。**
@Suite("过不去的两种")
struct NotSetUpIsNotAnErrorTests {
    private typealias Note = MusicSection.Note

    /// 三档各管各的：能不能按、要不要涂红、给不给门。
    @Test func eachKindAnswersItsOwnQuestion() {
        let hint = Note.hint("写一句提示词")
        let blocked = Note.blocked("额度不够")
        let setup = Note.setup("还没配好音乐模型")

        // 能不能按"生成"
        #expect(!hint.isBlocking)
        #expect(blocked.isBlocking)
        #expect(setup.isBlocking, "没配好却让他按生成 —— 按下去只会失败")

        // 要不要涂红
        #expect(!hint.isAlarming)
        #expect(blocked.isAlarming)
        #expect(!setup.isAlarming, "把'还没配好'涂成红色 —— 他什么都没做就被告知出事了")

        // 给不给门
        #expect(setup.needsSetup, "说了过不去，却没说往哪走 —— 一句红色的死胡同")
        #expect(!blocked.needsSetup)
        #expect(!hint.needsSetup)
    }

    /// 三句话都不是空的，而且各说各的。
    @Test func allThreeSaySomething() {
        let all = [Note.hint("a"), .blocked("b"), .setup("c")].map(\.text)
        #expect(all == ["a", "b", "c"])
    }
}
