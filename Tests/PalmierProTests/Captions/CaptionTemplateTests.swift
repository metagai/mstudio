import Foundation
import Testing
@testable import PalmierPro

@MainActor
@Suite struct CaptionTemplateTests {

    private func editorWithCaptions(_ contents: [String]) -> EditorViewModel {
        let e = EditorViewModel()
        var track = Track(type: .video)
        for (i, content) in contents.enumerated() {
            var clip = Fixtures.clip(id: "cap\(i)", mediaRef: "", start: i * 30, duration: 30)
            clip.mediaType = .text
            clip.textContent = content
            clip.captionGroupId = "group"
            clip.textStyle = TextStyle(fontSize: AppTheme.Caption.defaultFontSize)
            track.clips.append(clip)
        }
        e.timeline = Fixtures.timeline(tracks: [track])
        return e
    }

    private var karaoke: CaptionTemplate {
        CaptionTemplate.all.first { $0.id == "karaoke" }!
    }

    /// A size change must land in the box `CaptionLayout` would have produced at generation time,
    /// otherwise a restyled caption renders clipped.
    @Test func applyingATemplateRecomputesEachCaptionBox() {
        let e = editorWithCaptions(["First caption line", "Second, noticeably longer caption line"])
        let template = karaoke
        let canvas = CGSize(width: e.timeline.width, height: e.timeline.height)

        #expect(e.applyCaptionTemplate(template) == 2)

        for clip in e.timeline.tracks[0].clips {
            let expected = CaptionLayout.transform(
                for: clip.textContent ?? "", style: template.style,
                center: template.center, canvas: canvas
            )
            #expect(clip.textStyle == template.style)
            #expect(clip.textAnimation == template.animation)
            #expect(clip.transform.width == expected.width)
            #expect(clip.transform.height == expected.height)
            #expect(clip.transform.centerY == expected.centerY)
        }
        // Different text must not share a box.
        #expect(e.timeline.tracks[0].clips[0].transform.width != e.timeline.tracks[0].clips[1].transform.width)
    }

    @Test func restylingEveryCaptionIsOneUndoStep() {
        let e = editorWithCaptions(["one", "two", "three"])
        let manager = UndoManager()
        manager.groupsByEvent = false
        e.undo.attach(manager)
        let before = e.timeline.tracks[0].clips.map(\.textStyle)

        e.applyCaptionTemplate(karaoke)
        #expect(e.timeline.tracks[0].clips.map(\.textStyle) != before)

        manager.undo()
        #expect(e.timeline.tracks[0].clips.map(\.textStyle) == before)
        #expect(!manager.canUndo)
    }

    @Test func templateAppliesToNothingWhenTheTimelineHasNoCaptions() {
        let e = EditorViewModel()
        e.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [Fixtures.clip(start: 0, duration: 30)])])
        #expect(e.captionTextClipIds.isEmpty)
        #expect(e.applyCaptionTemplate(karaoke) == 0)
    }
}
