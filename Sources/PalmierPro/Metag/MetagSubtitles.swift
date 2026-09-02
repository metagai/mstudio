import Foundation

/// METAG 片子自带的字幕 → 编辑器的字幕 cue。
///
/// ## 为什么这条线值钱
///
/// Mac 有一整个字幕面板，而它拿字幕的唯一办法是**转写这条片子的旁白** ——
/// 慢、要联网、要额度，**而且不可能比原文更准：那段话本来就是我们写的**。
///
/// 网关那侧逐句合成时就把词级时间对齐好了，一直随任务详情发过来
/// （`subtitles`），只是 Mac 从没解过它。网关的注释写得很直白：
/// 「模板、词级对齐、出片三块能力各自建好很久，缺的就是这一根线。」
///
/// 转出来的是**已有的 `SubtitleCue`**，走**已有的**
/// `CaptionSpecBuilder` → `placeCaptionTrack` —— 不另开一条铺字幕的路，
/// 两条路迟早会不一样。
enum MetagSubtitles {
    /// 空的、时间不合法的一律丢掉 —— **一条零长度的字幕在时间线上是个鬼影**。
    static func cues(from subtitles: [MetagGateway.Job.Subtitle]) -> [SubtitleCue] {
        subtitles.compactMap { sub in
            let text = sub.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, sub.endTime > sub.startTime else { return nil }
            return SubtitleCue(
                text: text,
                startSeconds: sub.startTime,
                endSeconds: sub.endTime,
                words: sub.words.map { words in
                    words.compactMap { word in
                        let t = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty, word.endTime > word.startTime else { return nil }
                        return SubtitleCue.Word(
                            text: t, startSeconds: word.startTime, endSeconds: word.endTime
                        )
                    }
                }.flatMap { $0.isEmpty ? nil : $0 }
            )
        }
    }
}
