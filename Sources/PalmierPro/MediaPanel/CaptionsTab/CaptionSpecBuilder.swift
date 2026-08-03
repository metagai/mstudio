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
        let timelineEndFrame: Int
        let canvasWidth: Int
        let canvasHeight: Int
        let style: TextStyle
        let center: CGPoint
        let textCase: EditorViewModel.CaptionCase
        let maxWords: Int?
        let maxCharacters: Int?
        let gapSettings: CaptionGapSettings
        let animation: TextAnimation?

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
                maxCharacters: input.maxCharacters,
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
        return adjustedCaptionTiming(
            in: specs,
            settings: input.gapSettings,
            fps: input.fps,
            timelineEndFrame: input.timelineEndFrame
        )
    }

    /// Specs for imported subtitle cues. Honors the file's timing: overlaps are resolved but gaps are never closed.
    @concurrent
    static func build(
        cues: [SubtitleCue], fps: Int, canvasWidth: Int, canvasHeight: Int,
        style: TextStyle, center: CGPoint
    ) async throws -> [EditorViewModel.TextClipSpec] {
        let groupId = UUID().uuidString
        var specs: [EditorViewModel.TextClipSpec] = []
        for cue in cues {
            try Task.checkCancellation()
            let startFrame = Int((cue.startSeconds * Double(fps)).rounded())
            let endFrame = Int((cue.endSeconds * Double(fps)).rounded())
            specs.append(EditorViewModel.TextClipSpec(
                trackIndex: 0,
                startFrame: startFrame,
                durationFrames: max(1, endFrame - startFrame),
                content: cue.text,
                style: style,
                transform: CaptionLayout.transform(
                    for: cue.text, style: style, center: center,
                    canvas: CGSize(width: canvasWidth, height: canvasHeight)
                ),
                captionGroupId: groupId
            ))
        }
        // Zero-gap settings also make the trailing timeline-end hold a no-op.
        let honorFileTiming = CaptionGapSettings(maximumGapSeconds: 0) ?? .default
        return adjustedCaptionTiming(in: specs, settings: honorFileTiming, fps: fps, timelineEndFrame: 0)
    }

    private struct TimedCaption {
        var spec: EditorViewModel.TextClipSpec
        let originalDurationFrames: Int
    }

    private static func adjustedCaptionTiming(
        in specs: [EditorViewModel.TextClipSpec],
        settings: CaptionGapSettings,
        fps: Int,
        timelineEndFrame: Int
    ) -> [EditorViewModel.TextClipSpec] {
        let orderedIndices = specs.indices.sorted {
            let lhsStart = specs[$0].startFrame
            let rhsStart = specs[$1].startFrame
            return lhsStart == rhsStart ? $0 < $1 : lhsStart < rhsStart
        }
        var captions = orderedIndices.map {
            TimedCaption(spec: specs[$0], originalDurationFrames: specs[$0].durationFrames)
        }
        let maximumGapFrames = settings.maximumGapFrames(fps: fps)

        // Resolve collisions before extending captions across eligible gaps.
        for nextIndex in captions.indices.dropFirst() {
            let previousIndex = nextIndex - 1
            var previous = captions[previousIndex]
            var next = captions[nextIndex]
            resolveOverlap(previous: &previous, next: &next)
            captions[previousIndex] = previous
            captions[nextIndex] = next

            if maximumGapFrames > 0,
               let previousEnd = endFrame(of: captions[previousIndex].spec),
               let gap = positiveDistance(from: previousEnd, to: captions[nextIndex].spec.startFrame),
               gap <= maximumGapFrames,
               let duration = positiveDistance(
                   from: captions[previousIndex].spec.startFrame,
                   to: captions[nextIndex].spec.startFrame
               ) {
                captions[previousIndex].spec = resized(
                    captions[previousIndex].spec,
                    durationFrames: duration
                )
            }
        }

        if maximumGapFrames > 0,
           let lastIndex = captions.indices.last,
           let currentEnd = endFrame(of: captions[lastIndex].spec) {
            let available = timelineEndFrame.subtractingReportingOverflow(currentEnd)
            if !available.overflow {
                let holdFrames = min(maximumGapFrames, max(0, available.partialValue))
                let duration = captions[lastIndex].spec.durationFrames.addingReportingOverflow(holdFrames)
                if holdFrames > 0, !duration.overflow {
                    captions[lastIndex].spec = resized(
                        captions[lastIndex].spec,
                        durationFrames: duration.partialValue
                    )
                }
            }
        }
        return captions.map(\.spec)
    }

    private static func resolveOverlap(
        previous: inout TimedCaption,
        next: inout TimedCaption
    ) {
        guard let previousEnd = endFrame(of: previous.spec),
              next.spec.startFrame < previousEnd else { return }

        if next.spec.startFrame <= previous.spec.startFrame {
            // Preserve transcript order when starts quantize to the same frame.
            previous.spec = resized(previous.spec, durationFrames: 1)
            if let shiftedStart = endFrame(of: previous.spec) {
                shiftStartPreservingEnd(&next.spec, to: shiftedStart)
            }
            return
        }

        let overlap = positiveDistance(from: next.spec.startFrame, to: previousEnd)
        if overlap == 1, previous.originalDurationFrames < next.originalDurationFrames {
            // The shorter caption owns a one-frame rounding collision.
            shiftStartPreservingEnd(&next.spec, to: previousEnd)
            return
        }

        // Wider overlaps end at the next caption's authoritative start.
        if let duration = positiveDistance(
            from: previous.spec.startFrame,
            to: next.spec.startFrame
        ) {
            previous.spec = resized(previous.spec, durationFrames: duration)
        }
    }

    private static func endFrame(of spec: EditorViewModel.TextClipSpec) -> Int? {
        let result = spec.startFrame.addingReportingOverflow(spec.durationFrames)
        return result.overflow ? nil : result.partialValue
    }

    private static func positiveDistance(from start: Int, to end: Int) -> Int? {
        let result = end.subtractingReportingOverflow(start)
        return !result.overflow && result.partialValue > 0 ? result.partialValue : nil
    }

    private static func shiftStartPreservingEnd(
        _ spec: inout EditorViewModel.TextClipSpec,
        to startFrame: Int
    ) {
        let wordOffsetFrames = positiveDistance(from: spec.startFrame, to: startFrame) ?? 0
        let originalEnd = endFrame(of: spec)
        spec.startFrame = startFrame
        let durationFrames = originalEnd.flatMap {
            positiveDistance(from: startFrame, to: $0)
        } ?? 1
        spec = resized(
            spec,
            durationFrames: durationFrames,
            wordOffsetFrames: wordOffsetFrames
        )
    }

    private static func resized(
        _ spec: EditorViewModel.TextClipSpec,
        durationFrames: Int,
        wordOffsetFrames: Int = 0
    ) -> EditorViewModel.TextClipSpec {
        var resized = spec
        resized.durationFrames = durationFrames
        guard let originalWords = resized.words else { return resized }

        var words = originalWords.compactMap { word -> WordTiming? in
            let shiftedStart = word.startFrame.subtractingReportingOverflow(wordOffsetFrames)
            let shiftedEnd = word.endFrame.subtractingReportingOverflow(wordOffsetFrames)
            let start = min(max(0, shiftedStart.overflow ? 0 : shiftedStart.partialValue), durationFrames)
            let end = min(max(start, shiftedEnd.overflow ? 0 : shiftedEnd.partialValue), durationFrames)
            return end > start
                ? WordTiming(text: word.text, startFrame: start, endFrame: end)
                : nil
        }
        resized.words = words.isEmpty ? nil : words
        return resized
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
