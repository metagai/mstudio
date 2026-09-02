import Foundation
import Testing
@testable import PalmierPro

/// **片子自带字幕，而这个面板一直在转写自己的旁白去拿字幕。**
///
/// 网关逐句合成时就把词级时间对齐好了，一直随任务详情发过来 ——
/// Mac 有一整个字幕面板，却从没解过那个字段。它拿字幕的唯一办法是
/// 转写这条片子的旁白：慢、要联网、要额度，
/// **而且不可能比原文更准：那段话本来就是我们写的。**
@Suite("片子自带的字幕")
struct MetagSubtitlesTests {
    private static func sub(_ text: String, _ s: Double, _ e: Double,
                            words: [(String, Double, Double)]? = nil) -> MetagGateway.Job.Subtitle {
        let json: [String: Any] = [
            "text": text, "startTime": s, "endTime": e,
            "words": words?.map { ["text": $0.0, "startTime": $0.1, "endTime": $0.2] } as Any,
        ].compactMapValues { $0 is NSNull ? nil : $0 }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(MetagGateway.Job.Subtitle.self, from: data)
    }

    @Test func wordTimingSurvivesTheTrip() {
        let cues = MetagSubtitles.cues(from: [
            Self.sub("she folds the last shirt", 0, 2.4,
                     words: [("she", 0, 0.4), ("folds", 0.4, 1.0), ("the last shirt", 1.0, 2.4)]),
        ])
        #expect(cues.count == 1)
        #expect(cues[0].words?.count == 3)
        #expect(cues[0].words?.first?.text == "she")
    }

    /// **一条零长度的字幕在时间线上是个鬼影** —— 丢掉。
    @Test(arguments: [("", 0.0, 2.0), ("   ", 0.0, 2.0), ("ok", 2.0, 2.0), ("ok", 3.0, 1.0)])
    func nonsenseCuesAreDropped(text: String, start: Double, end: Double) {
        #expect(MetagSubtitles.cues(from: [Self.sub(text, start, end)]).isEmpty)
    }

    /// 词里的垃圾也要丢，但**不能因此丢掉整句**。
    @Test func badWordsDoNotKillTheCue() {
        let cues = MetagSubtitles.cues(from: [
            Self.sub("hello", 0, 1, words: [("", 0, 0.5), ("hello", 0.5, 1.0)]),
        ])
        #expect(cues.count == 1)
        #expect(cues[0].words?.count == 1)
    }

    /// 一个词都不剩就当没有词 —— 不留一个空数组。
    @Test func noUsableWordsMeansNoWords() {
        let cues = MetagSubtitles.cues(from: [Self.sub("hello", 0, 1, words: [("", 0, 0)])])
        #expect(cues[0].words == nil)
    }

    /// 没有 words 的（SRT / WebVTT 那一支）照旧能用。
    @Test func cuesWithoutWordsStillWork() {
        #expect(MetagSubtitles.cues(from: [Self.sub("hello", 0, 1)]).first?.words == nil)
    }

    /// **词级时间要真的落到片段上，而且是片段内的相对帧。**
    ///
    /// 第一版判据只比到 `cues`，于是把 `CaptionSpecBuilder` 里那段词级转换
    /// 整个删掉，判据照样全绿 —— 卡拉OK 模板又会是空的，而没有东西会红。
    /// 判到 cue 为止，就只证明了"我们读到了"，没证明"它到得了时间线"。
    @Test func wordsSurviveIntoTheClip() async throws {
        let cue = SubtitleCue(
            text: "she folds the last shirt",
            startSeconds: 1.0, endSeconds: 3.0,
            words: [
                .init(text: "she", startSeconds: 1.0, endSeconds: 1.5),
                .init(text: "folds", startSeconds: 1.5, endSeconds: 3.0),
            ]
        )
        let specs = try await CaptionSpecBuilder.build(
            cues: [cue], fps: 30, canvasWidth: 1920, canvasHeight: 1080,
            style: .caption, center: CGPoint(x: 0.5, y: 0.8)
        )
        let words = try #require(specs.first?.words, "词级时间没落到片段上 —— 卡拉OK 模板会是空的")
        #expect(words.count == 2)
        // 片段从第 30 帧开始，所以第一个词在片段内是第 0 帧 —— **相对，不是绝对**。
        #expect(words[0].startFrame == 0)
        #expect(words[0].endFrame == 15)
        #expect(words[1].startFrame == 15)
    }

    /// 没有词的 cue 不该凭空长出一个空数组。
    @Test func aCueWithoutWordsProducesNoWords() async throws {
        let specs = try await CaptionSpecBuilder.build(
            cues: [SubtitleCue(text: "hello", startSeconds: 0, endSeconds: 1, words: nil)],
            fps: 30, canvasWidth: 1920, canvasHeight: 1080,
            style: .caption, center: CGPoint(x: 0.5, y: 0.8)
        )
        #expect(specs.first?.words == nil)
    }

    /// **走已有那条路** —— 不另开一个铺字幕的实现。
    @Test func itReusesTheExistingCaptionPath() throws {
        let src = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/PalmierPro/Metag/MetagJobOpener.swift"),
            encoding: .utf8
        )
        #expect(src.contains("CaptionSpecBuilder.build("))
        #expect(src.contains("editor.placeCaptionTrack(specs, actionName: \"Add Captions\")"),
                "又自己搭了一条铺字幕的路 —— 两条路迟早会不一样")
        #expect(src.contains("if added > 0, let subs = job.subtitles"),
                "一镜都没取到还去铺字幕 —— 那是一条盖在空时间线上的字幕轨")
    }
}
