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
        /// 时间线总帧数。最后一条字幕的延长不能越过片尾。
        let timelineEndFrame: Int
        /// 跨过多短的停顿仍保持字幕可见，同时也是最后一条的按住时长。
        /// 默认 0.5 秒 —— 换气的空档大多在这个量级以内。
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
        return adjustedCaptionTiming(
            in: specs,
            settings: input.gapSettings,
            fps: input.fps,
            timelineEndFrame: input.timelineEndFrame
        )
    }

    /// 按 `durationFrames` 重建一条字幕。
    ///
    /// **重建而不是就地改。** TextClipSpec 的时间字段是 let，上游为这项改动把它们
    /// 改成了 var —— 那是放宽一个被很多处依赖的公共类型的不可变性。
    private static func resized(
        _ spec: EditorViewModel.TextClipSpec,
        durationFrames: Int
    ) -> EditorViewModel.TextClipSpec {
        var words = spec.words
        // wordCycle 的最后一个词要跟着延长，否则字幕在延长段里是空的。
        if spec.animation?.preset == .wordCycle, let last = words?.indices.last {
            words?[last].endFrame = durationFrames
        }
        return EditorViewModel.TextClipSpec(
            trackIndex: spec.trackIndex,
            startFrame: spec.startFrame,
            durationFrames: durationFrames,
            content: spec.content,
            style: spec.style,
            transform: spec.transform,
            captionGroupId: spec.captionGroupId,
            words: words,
            animation: spec.animation,
            fillMode: spec.fillMode
        )
    }

    /// 把短于阈值的空档合并进前一条字幕，并把最后一条按同一个阈值多按住一会儿。
    ///
    /// 最后一条没有"下一条"可以合并过去，于是一条很短的收尾字幕会闪一下就没了 ——
    /// 那正是最需要读清楚的一句（上游 5ddc2fa）。延长量受片尾约束，不越过时间线。
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
    private static func adjustedCaptionTiming(
        in specs: [EditorViewModel.TextClipSpec],
        settings: CaptionGapSettings,
        fps: Int,
        timelineEndFrame: Int
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
                        adjusted[coverageIndex] = resized(
                            adjusted[coverageIndex], durationFrames: duration
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

        let (available, availableOverflow) = timelineEndFrame
            .subtractingReportingOverflow(coverageEnd)
        if !availableOverflow, available > 0 {
            let hold = min(maximumGapFrames, available)
            let (held, heldOverflow) = adjusted[coverageIndex].durationFrames
                .addingReportingOverflow(hold)
            if hold > 0, !heldOverflow {
                adjusted[coverageIndex] = resized(adjusted[coverageIndex], durationFrames: held)
            }
        }
        return adjusted
    }
}
