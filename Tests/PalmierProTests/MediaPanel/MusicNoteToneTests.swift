import Foundation
import Testing
@testable import PalmierPro

/// **"你还没说要什么"不是一个错误。**
///
/// 2026-09-02 把音乐那块面板渲成图第一次看见：唯一的一处红字是
/// 「说说你想要什么样的音乐」—— 而它出现在他**什么都还没做**的时候。
/// 打开面板就是一行红字，等于开门先说他错了。
///
/// 那一段把四种不同的东西刷成同一个颜色：
/// 「还没说要什么」「时间线上还没视频」（他没动手）、
/// 「没有可用模型」「credits 不够」「参数不合法」（真的过不去）。
@Suite("音乐面板那一行提示的语气")
struct MusicNoteToneTests {
    /// **他什么都还没做的那两种情况，不许上红。**
    ///
    /// 这一条直接问那个判断本身，不比源码里那一行 ——
    /// 上一版只会断言 `Note.hint(...).isBlocking == false`（一句同义反复），
    /// 把生产代码里的 `.hint` 改成 `.blocked` 它一声不响。
    @Test(arguments: [
        (true, true, false, "文字模式，一个字都还没打"),
        (false, true, false, "配乐模式，时间线上还没视频"),
    ])
    func notActedYetIsAHintNotAnError(isText: Bool, empty: Bool, hasSource: Bool, why: String) throws {
        let note = try #require(
            MusicSection.missingInputHint(isTextMode: isText, promptIsEmpty: empty, hasSource: hasSource),
            "\(why)的时候一句话都不说")
        #expect(!note.isBlocking, "\(why)就给他一行红字 —— 开门先说他错了")
    }

    /// 他做了该做的，这一行就该消失，不是换个颜色继续挂着。
    @Test(arguments: [(true, false, false), (false, true, true)])
    func onceHeHasActedTheHintGoesAway(isText: Bool, empty: Bool, hasSource: Bool) {
        #expect(MusicSection.missingInputHint(
            isTextMode: isText, promptIsEmpty: empty, hasSource: hasSource) == nil)
    }

    /// 真过不去的仍然是红的 —— 分档不是把所有话都变软。
    @Test func aBlockerStaysRed() {
        #expect(MusicSection.Note.blocked("credits 不够").isBlocking)
    }

    /// **两档都还能拦住「生成」。** 语气变了，闸门不能变 ——
    /// 灰色的引导底下如果按钮亮了，他按下去就是一次白扣费。
    @Test func bothKindsStillBlockGenerating() throws {
        let src = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/PalmierPro/MediaPanel/AudioPanelTab/MusicTab.swift"),
            encoding: .utf8)
        #expect(src.contains("model != nil && validationNote == nil && !isGenerating"),
                "分档之后「生成」的闸门被改动了 —— 引导变灰不代表可以按")
        // 颜色是**按档选的**，不是写死一个。
        #expect(src.contains("message.isBlocking"), "又把所有提示刷成同一个颜色了")
    }
}
