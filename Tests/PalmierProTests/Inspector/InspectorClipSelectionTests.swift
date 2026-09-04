import Testing
@testable import PalmierPro

@Suite struct InspectorClipSelectionTests {
    @Test func resolvesSelectedClipsByInspectorCategory() {
        let text = Fixtures.clip(id: "text", mediaRef: "text", mediaType: .text, start: 0, duration: 30)
        let video = Fixtures.clip(id: "video", mediaRef: "video", mediaType: .video, start: 30, duration: 30)
        let audio = Fixtures.clip(id: "audio", mediaRef: "audio", mediaType: .audio, start: 0, duration: 60)
        let unselected = Fixtures.clip(id: "other", mediaRef: "other", mediaType: .text, start: 60, duration: 30)
        let timeline = Fixtures.timeline(tracks: [
            Fixtures.videoTrack(clips: [text, video, unselected]),
            Fixtures.audioTrack(clips: [audio]),
        ])

        let selection = InspectorClipSelection.resolve(
            timeline: timeline,
            selectedIds: [text.id, video.id, audio.id]
        )

        #expect(selection.textClips.map(\.id) == [text.id])
        #expect(selection.nonTextVisualClips.map(\.id) == [video.id])
        #expect(selection.audioClips.map(\.id) == [audio.id])
        #expect(selection.firstVisualClip?.id == text.id)
        #expect(selection.clipCount == 3)
    }

    @Test func largeCaptionSelectionResolvesWithinInteractionBudget() {
        let captions = (0..<10_000).map { index in
            Fixtures.clip(
                id: "caption-\(index)",
                mediaRef: "caption-media",
                mediaType: .text,
                start: index * 30,
                duration: 30
            )
        }
        let timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: captions)])
        let selectedIds = Set(captions.map(\.id))

        var selection = InspectorClipSelection()
        let duration = ContinuousClock().measure {
            selection = InspectorClipSelection.resolve(timeline: timeline, selectedIds: selectedIds)
        }

        #expect(selection.textClips.count == captions.count)
        // **墙上时钟，跑在一套 2000 多条并行的测试里。**
        //
        // 250ms 那一版单跑 0.12 秒过、满载并行 0.31 秒红 —— 一条偶发红，
        // 而**偶发红比永远绿更阴险**：它教会所有人忽略红色，
        // 然后在它某天报真事的那一天被同一个动作挥手放过。
        //
        // 放到 1 秒：它守的是"选中一个片段要像瞬间完成"，
        // 而真正的回归（把 O(n) 写成 O(n²)）是十倍百倍，不是 1.2 倍。
        // **留下的余量吃掉的是机器噪音，不是回归。**
        //
        // 更好的修法是量做了多少次工，不是量了多少秒 —— 记在 docs/todo.md。
        #expect(duration < .seconds(1))
    }
}
