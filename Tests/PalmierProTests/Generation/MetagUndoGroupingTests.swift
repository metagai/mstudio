import Testing
import Foundation
@testable import PalmierPro

/// Fixing several flagged shots is one user intent, so it has to undo as one action.
/// Registering per shot means ⌘Z after one click only puts back the last one.
@Suite("METAG 撤销分组")
@MainActor
struct MetagUndoGroupingTests {

    private func editorWithAssets(_ count: Int) -> (EditorViewModel, [MediaAsset]) {
        let editor = EditorViewModel()
        let assets = (0..<count).map { i -> MediaAsset in
            let a = MediaAsset(
                url: URL(fileURLWithPath: "/tmp/shot_\(i).mp4"),
                type: .video,
                name: "shot_\(i).mp4"
            )
            var input = GenerationInput(prompt: "p\(i)", model: "local", duration: 3, aspectRatio: "16:9")
            input.backendJobId = "j1"
            input.outputIndex = i
            a.generationInput = input
            return a
        }
        editor.mediaAssets = assets
        return (editor, assets)
    }

    @Test("多镜一起换，只产生一次撤销")
    func batchSwapIsOneUndoStep() throws {
        let manager = UndoManager()
        manager.groupsByEvent = false
        let (editor, assets) = editorWithAssets(3)
        editor.undo.attach(manager)

        let staged = assets.map { ($0, $0.url, URL(fileURLWithPath: "/tmp/new_\($0.name)")) }
        editor.undo.perform("Fix Flagged Shots") {
            editor.registerTimelineUndo("Fix Flagged Shots") { vm in
                for item in staged { vm.relinkAsset(id: item.0.id, to: item.1) }
            }
            for item in staged { editor.relinkAsset(id: item.0.id, to: item.2) }
        }

        #expect(editor.mediaAssets.allSatisfy { $0.url.lastPathComponent.hasPrefix("new_") })
        // 一次撤销要把三镜一起放回去
        manager.undo()
        #expect(editor.mediaAssets.allSatisfy { !$0.url.lastPathComponent.hasPrefix("new_") })
    }

    @Test("按来源定位，顺序打乱也换对镜头")
    func resolvesByProvenanceNotOrder() {
        let (editor, assets) = editorWithAssets(3)
        editor.mediaAssets = [assets[2], assets[0], assets[1]]
        #expect(editor.asset(forJob: "j1", shotIndex: 2)?.id == assets[2].id)
        #expect(editor.asset(forJob: "j1", shotIndex: 0)?.id == assets[0].id)
    }
}
