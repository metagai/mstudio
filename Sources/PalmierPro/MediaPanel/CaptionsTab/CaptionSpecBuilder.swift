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
                captionGroupId: groupId,
                // 词级时间跟着走。**帧是相对这一段自己的** ——
                // 卡拉OK 高亮是在片段内部走的，不是在时间线上走的。
                // SRT / WebVTT 没有词，那一支照旧是 nil。
                words: cue.words.map { words in
                    words.compactMap { word -> WordTiming? in
                        let ws = Int((word.startSeconds * Double(fps)).rounded()) - startFrame
                        let we = Int((word.endSeconds * Double(fps)).rounded()) - startFrame
                        let clampedStart = max(0, min(ws, endFrame - startFrame))
                        let clampedEnd = max(clampedStart, min(we, endFrame - startFrame))
                        guard clampedEnd > clampedStart else { return nil }
                        return WordTiming(text: word.text, startFrame: clampedStart, endFrame: clampedEnd)
                    }
                }.flatMap { $0.isEmpty ? nil : $0 }
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


}
