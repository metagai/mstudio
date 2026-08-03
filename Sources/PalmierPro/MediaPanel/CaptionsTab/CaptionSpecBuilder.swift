import CoreGraphics
import Foundation

enum CaptionSpecBuilder {
    struct Target: Sendable {
        let clip: Clip
        let result: TranscriptionResult
    }

    struct Input: Sendable {
        let targets: [Target]
        let fps: Int
        let canvasWidth: Int
        let canvasHeight: Int
        let style: TextStyle
        let center: CGPoint
        let textCase: EditorViewModel.CaptionCase
        let maxWords: Int?
        let animation: TextAnimation?
        /// 跨过多短的停顿仍保持字幕可见。默认 0.25 秒 ——
        /// 换气的空档大多在这个量级以内。
        var gapSettings: CaptionGapSettings = .default

        var canvas: CGSize { CGSize(width: canvasWidth, height: canvasHeight) }
    }

    @concurrent
    static func build(_ input: Input) async throws -> [EditorViewModel.TextClipSpec] {
        try Task.checkCancellation()
        let groupId = UUID().uuidString
        var specs: [EditorViewModel.TextClipSpec] = []

        for target in input.targets {
            try Task.checkCancellation()
            let phrases = CaptionTranscriptMapper.phrases(
                for: target.clip,
                result: target.result,
                fps: input.fps,
                maxWords: input.maxWords,
                minDuration: AppTheme.Caption.minDisplayDuration,
                fits: { text in
                    if Task.isCancelled { return true }
                    return CaptionLayout.fits(text, style: input.style, canvas: input.canvas)
                }
            )
            try Task.checkCancellation()
            guard !phrases.isEmpty else { continue }

            let cased = phrases.map {
                CaptionBuilder.Phrase(
                    text: input.textCase.apply($0.text),
                    start: $0.start,
                    end: $0.end,
                    words: $0.words
                )
            }
            specs.append(contentsOf: CaptionBuilder.specs(
                for: cased,
                sourceClip: target.clip,
                trackIndex: 0,
                fps: input.fps,
                style: input.style,
                captionGroupId: groupId,
                animation: input.animation,
                transformFor: { text in
                    guard !Task.isCancelled else { return nil }
                    return CaptionLayout.transform(
                        for: text, style: input.style, center: input.center, canvas: input.canvas
                    )
                }
            ))
            try Task.checkCancellation()
        }
        return closingShortGaps(in: specs, settings: input.gapSettings, fps: input.fps)
    }

    /// 把短于阈值的空档合并进前一条字幕。
    ///
    /// 来自上游 1d76782，**只取纯时间轴计算那部分**（那个提交把它和
    /// 云端转写 #429 捆在一起，而我们一律端侧）。
    ///
    /// 三处细节都是有理由的，别"简化"掉：
    ///   · 溢出全部用 addingReportingOverflow —— 帧数是 Int，
    ///     一条坏输入不该让整次生成崩掉；
    ///   · 有入场动画的下一条要多盖 1 帧，否则交接处会闪
    ///     （见 TextAnimation.Preset.needsIncomingCaptionCoverage）；
    ///   · wordCycle 的最后一个词要跟着延长，否则字幕在延长段里是空的。
    private static func closingShortGaps(
        in specs: [EditorViewModel.TextClipSpec],
        settings: CaptionGapSettings,
        fps: Int
    ) -> [EditorViewModel.TextClipSpec] {
        let maximumGapFrames = settings.maximumGapFrames(fps: fps)
        guard maximumGapFrames > 0, !specs.isEmpty else { return specs }

        var adjusted = specs
        let ordered = adjusted.indices.sorted {
            let lhs = adjusted[$0].startFrame
            let rhs = adjusted[$1].startFrame
            return lhs == rhs ? $0 < $1 : lhs < rhs
        }
        guard let firstIndex = ordered.first else { return adjusted }
        var coverageIndex = firstIndex
        let (firstEnd, firstOverflow) = adjusted[firstIndex].startFrame
            .addingReportingOverflow(adjusted[firstIndex].durationFrames)
        var coverageEnd = firstOverflow ? adjusted[firstIndex].startFrame : firstEnd

        for nextIndex in ordered.dropFirst() {
            let next = adjusted[nextIndex]
            if next.startFrame > coverageEnd {
                let (gap, gapOverflow) = next.startFrame.subtractingReportingOverflow(coverageEnd)
                if !gapOverflow, gap <= maximumGapFrames {
                    let overlap = next.animation?.preset.needsIncomingCaptionCoverage == true ? 1 : 0
                    let (closedEnd, endOverflow) = next.startFrame.addingReportingOverflow(overlap)
                    let previousStart = adjusted[coverageIndex].startFrame
                    let (duration, durationOverflow) = closedEnd
                        .subtractingReportingOverflow(previousStart)
                    if !endOverflow, !durationOverflow, duration > 0 {
                        // **重建而不是就地改。** TextClipSpec 的时间字段是 let，
                        // 上游为这项改动把它们改成了 var —— 那是放宽一个被很多处
                        // 依赖的公共类型的不可变性，代价远大于这里多写六行。
                        let previous = adjusted[coverageIndex]
                        var words = previous.words
                        if previous.animation?.preset == .wordCycle,
                           let last = words?.indices.last {
                            words?[last].endFrame = duration
                        }
                        adjusted[coverageIndex] = EditorViewModel.TextClipSpec(
                            trackIndex: previous.trackIndex,
                            startFrame: previous.startFrame,
                            durationFrames: duration,
                            content: previous.content,
                            style: previous.style,
                            transform: previous.transform,
                            captionGroupId: previous.captionGroupId,
                            words: words,
                            animation: previous.animation,
                            fillMode: previous.fillMode
                        )
                        coverageEnd = closedEnd
                    }
                }
            }
            let (nextEnd, nextOverflow) = next.startFrame
                .addingReportingOverflow(next.durationFrames)
            let resolvedEnd = nextOverflow ? next.startFrame : nextEnd
            if resolvedEnd >= coverageEnd {
                coverageIndex = nextIndex
                coverageEnd = resolvedEnd
            }
        }
        return adjusted
    }
}
