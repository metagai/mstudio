import CoreGraphics
import Foundation

extension EditorViewModel {
    /// Caption text clips in the active timeline, in track order.
    var captionTextClipIds: [String] {
        timeline.tracks.flatMap(\.clips)
            .filter { $0.mediaType == .text && $0.captionGroupId != nil }
            .map(\.id)
    }

    /// Restyles existing captions to a template as one undoable action. The box is recomputed
    /// through `CaptionLayout`, so a size change can't leave text clipped by a stale transform.
    @discardableResult
    func applyCaptionTemplate(_ template: CaptionTemplate, clipIds: [String]? = nil) -> Int {
        let ids = clipIds ?? captionTextClipIds
        guard !ids.isEmpty else { return 0 }
        let canvas = CGSize(width: max(1, timeline.width), height: max(1, timeline.height))
        var applied = 0
        commitClipProperties(clipIds: ids, actionName: "Apply Caption Template") { clip in
            guard clip.mediaType == .text else { return }
            clip.textStyle = template.style
            clip.textAnimation = template.animation
            clip.transform = CaptionLayout.transform(
                for: clip.textContent ?? "",
                style: template.style,
                center: template.center,
                canvas: canvas
            )
            applied += 1
        }
        return applied
    }
}
