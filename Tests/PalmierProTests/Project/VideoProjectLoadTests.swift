import Foundation
import Observation
import Testing
@testable import PalmierPro

@MainActor
private final class MediaAssetsChangeCounter {
    private weak var editor: EditorViewModel?
    private(set) var count = 0

    init(editor: EditorViewModel) {
        self.editor = editor
        observe()
    }

    private func observe() {
        guard let editor else { return }
        withObservationTracking {
            _ = editor.mediaAssets.count
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.count += 1
                self.observe()
            }
        }
    }
}

/// A corrupt `media.json` must never make a project unopenable: the timeline lives in a
/// separate file and is the real creative work. A bad manifest should degrade to "media
/// offline" (like a missing manifest already does), and the original bytes must be preserved
/// on disk so a newer build (e.g. after a schema change) can still recover the library.
/// ⚠ `.serialized`：这一组要读写真文件、还要等两层没句柄的游离 Task 跑完。
///
/// 2026-09-03：和另外 2000 多条测试抢机器时，那两层任务**根本跑不完** ——
/// 预算从 1 秒提到 45 秒，它在 67 秒时还是没等到。
/// 那不是"机器慢"，是那棵任务树在满载下饿死了。
///
/// **不缩小它断言的东西来让它变绿**（那是「换问法」，第四十条），
/// 也不再往上加预算（加到多少都是赌）。让它单独跑。
/// 真正的修法是给那棵任务树一个句柄，已记进 `docs/todo.md`。
@Suite("VideoProject package load resilience", .serialized)
struct VideoProjectLoadTests {

    private let fm = FileManager.default

    private func makeBundle(tracks: Int = 1) throws -> URL {
        let bundle = fm.temporaryDirectory
            .appendingPathComponent("vp-load-\(UUID().uuidString).metag", isDirectory: true)
        try fm.createDirectory(at: bundle, withIntermediateDirectories: true)
        let timeline = Fixtures.timeline(
            tracks: (0..<tracks).map { _ in Fixtures.videoTrack(clips: [Fixtures.clip(start: 0, duration: 30)]) }
        )
        try JSONEncoder().encode(timeline)
            .write(to: bundle.appendingPathComponent(Project.timelineFilename))
        return bundle
    }

    private func sampleManifest() -> MediaManifest {
        var m = MediaManifest()
        m.entries = [
            MediaManifestEntry(id: "a", name: "A", type: .video,
                               source: .project(relativePath: "media/a.mp4"), duration: 1)
        ]
        return m
    }

    // MARK: - Read: graceful degrade

    @Test func corruptManifestStillOpensWithIntactTimeline() throws {
        let bundle = try makeBundle(tracks: 2)
        defer { try? fm.removeItem(at: bundle) }
        try Data("{ this is not valid manifest json ".utf8)
            .write(to: bundle.appendingPathComponent(Project.manifestFilename))

        let contents = try VideoProject.readProjectPackage(at: bundle)   // must NOT throw

        #expect(contents.manifest == nil)
        #expect(contents.manifestUnreadable == true)
        #expect(contents.projectFile.timelines.first?.tracks.count == 2)   // creative work survives
    }

    @Test func missingManifestOpensAndIsNotFlaggedUnreadable() throws {
        let bundle = try makeBundle()
        defer { try? fm.removeItem(at: bundle) }

        let contents = try VideoProject.readProjectPackage(at: bundle)

        #expect(contents.manifest == nil)
        #expect(contents.manifestUnreadable == false)   // missing != corrupt
    }

    @Test func validManifestDecodesNormally() throws {
        let bundle = try makeBundle()
        defer { try? fm.removeItem(at: bundle) }
        try JSONEncoder().encode(sampleManifest())
            .write(to: bundle.appendingPathComponent(Project.manifestFilename))

        let contents = try VideoProject.readProjectPackage(at: bundle)

        #expect(contents.manifest?.entries.count == 1)
        #expect(contents.manifestUnreadable == false)
    }

    @MainActor
    @Test func manifestRestorePublishesMediaAssetsOnce() {
        let document = VideoProject()
        var manifest = MediaManifest()
        manifest.entries = (0..<100).map { index in
            MediaManifestEntry(
                id: "asset-\(index)",
                name: "Asset \(index)",
                type: .video,
                source: .external(absolutePath: "/tmp/asset-\(index).mp4"),
                duration: 1
            )
        }
        document.editorViewModel.mediaManifest = manifest
        let changes = MediaAssetsChangeCounter(editor: document.editorViewModel)

        document.restoreAssetsFromManifest()

        #expect(changes.count == 1)
        #expect(document.editorViewModel.mediaAssets.count == manifest.entries.count)
        #expect(document.editorViewModel.mediaAssetsById.count == manifest.entries.count)
    }

    @MainActor
    @Test func manifestRestoreLoadsUnusedMetadataWithoutVisuals() async throws {
        let imageURL = try CompositorFixtures.patternPNG(size: CGSize(width: 640, height: 360))
        let document = VideoProject()
        var manifest = MediaManifest()
        manifest.entries = [MediaManifestEntry(
            id: "unused-image",
            name: "Unused Image",
            type: .image,
            source: .external(absolutePath: imageURL.path),
            duration: Defaults.imageDurationSeconds
        )]
        document.editorViewModel.mediaManifest = manifest

        document.restoreAssetsFromManifest()
        for _ in 0..<100 {
            if document.editorViewModel.mediaAssets.first?.sourceWidth == 640 { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        let asset = try #require(document.editorViewModel.mediaAssets.first)
        #expect(asset.sourceWidth == 640)
        #expect(asset.sourceHeight == 360)
        #expect(asset.thumbnail == nil)
        #expect(document.editorViewModel.mediaVisualCache.imageThumbnail(for: asset.id) == nil)
    }

    @MainActor
    @Test func manifestRestoreRefreshesTimelineMetadataWithoutThumbnail() async throws {
        let imageURL = try CompositorFixtures.patternPNG(size: CGSize(width: 640, height: 360))
        let document = VideoProject()
        document.editorViewModel.timeline = Fixtures.timeline(tracks: [
            Fixtures.videoTrack(clips: [Fixtures.clip(
                mediaRef: "used-image",
                mediaType: .image,
                start: 0,
                duration: 30
            )])
        ])
        var manifest = MediaManifest()
        manifest.entries = [
            MediaManifestEntry(
                id: "used-image",
                name: "Used Image",
                type: .image,
                source: .external(absolutePath: imageURL.path),
                duration: Defaults.imageDurationSeconds,
                sourceWidth: 1,
                sourceHeight: 1
            ),
            MediaManifestEntry(
                id: "unused-image",
                name: "Unused Image",
                type: .image,
                source: .external(absolutePath: imageURL.path),
                duration: Defaults.imageDurationSeconds,
                sourceWidth: 2,
                sourceHeight: 2
            ),
        ]
        document.editorViewModel.mediaManifest = manifest

        document.restoreAssetsFromManifest()
        // **预算给足，而且超时要说清是超时。**
        // 原来是 `for _ in 0..<100 { sleep(10ms) }` —— 总共 1 秒，
        // 整套测试并行跑时不够，五次里红两次。
        // 门里一条偶发红比没有判据更糟：**它教会所有人忽略红色。**
        // ⚠ **预算 45 秒，而且这是个症状，不是修法。**
        //
        // 还原起的是**两层没有句柄的游离 Task**：一层扫文件是否存在，
        // 一层每个素材各起一个（`loadMetadata` → `prepareMediaVisuals`）。
        // 外面没有任何可以 await 的口子，所以这里只能等。
        //
        // 10 秒不够（满载并行时 13.9 秒才失败）。真正的修法是给那一整棵
        // 任务树一个句柄 —— 那样测试能确定地等，而且**关闭工程时能取消**
        // （AGENTS.md 明写：游离 Task 必须有 owner）。已记进 docs/todo.md。
        //
        // **不缩小它断言的东西来让它变绿** —— 那是「换问法」，
        // 判据会绿而用户拿到的东西一点没变（lessons 第四十条）。
        let restored = await AsyncWait.until("清单还原补上缩略图和尺寸", timeout: .seconds(20)) {
            document.editorViewModel.mediaVisualCache.imageThumbnail(for: "used-image") != nil
                && document.editorViewModel.mediaAssets
                    .first { $0.id == "unused-image" }?.sourceWidth == 640
        }
        try #require(restored, "等了 10 秒，清单还原还没补完 —— 这是超时，不一定是功能坏了")

        let used = try #require(document.editorViewModel.mediaAssets.first { $0.id == "used-image" })
        let unused = try #require(document.editorViewModel.mediaAssets.first { $0.id == "unused-image" })
        #expect(used.sourceWidth == 640)
        #expect(used.sourceHeight == 360)
        #expect(used.thumbnail == nil)
        #expect(unused.sourceWidth == 640)
        #expect(unused.sourceHeight == 360)
        #expect(unused.thumbnail == nil)
        #expect(document.editorViewModel.mediaVisualCache.imageThumbnail(for: used.id) != nil)
        #expect(document.editorViewModel.mediaVisualCache.imageThumbnail(for: unused.id) == nil)
    }

    @MainActor
    @Test func libraryThumbnailLoadsOnDemand() async throws {
        let imageURL = try CompositorFixtures.patternPNG(size: CGSize(width: 640, height: 360))
        let asset = MediaAsset(url: imageURL, type: .image, name: "Lazy Image")

        await asset.loadLibraryThumbnail()

        let thumbnail = try #require(asset.thumbnail)
        #expect(asset.sourceWidth == 640)
        #expect(asset.sourceHeight == 360)
        #expect(max(thumbnail.size.width, thumbnail.size.height) <= 320)
    }

    @MainActor
    @Test func placingDeferredImageStartsTimelineThumbnail() async throws {
        let imageURL = try CompositorFixtures.patternPNG(size: CGSize(width: 640, height: 360))
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack()])
        let asset = MediaAsset(url: imageURL, type: .image, name: "Deferred Image")
        editor.importMediaAsset(asset)

        _ = editor.placeClip(asset: asset, trackIndex: 0, startFrame: 0, durationFrames: 30)
        for _ in 0..<100 {
            if editor.mediaVisualCache.imageThumbnail(for: asset.id) != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(editor.mediaVisualCache.imageThumbnail(for: asset.id) != nil)
    }

    @Test func missingTimelineStillThrows() throws {
        // project.json is the required file — degrading it would hide real corruption.
        let bundle = fm.temporaryDirectory
            .appendingPathComponent("vp-empty-\(UUID().uuidString).metag", isDirectory: true)
        try fm.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: bundle) }

        #expect(throws: (any Error).self) {
            try VideoProject.readProjectPackage(at: bundle)
        }
    }

    // MARK: - Save: don't overwrite the original with an empty manifest

    @Test func emptyManifestNotSerializedAfterLoadFailure() {
        // Opening with a corrupt manifest leaves an empty in-memory manifest. Serializing it
        // would overwrite the (recoverable) original on the next autosave — so it must be nil.
        #expect(VideoProject.manifestSnapshot(manifest: MediaManifest(), loadFailed: true) == nil)
    }

    @Test func rebuiltManifestIsSerializedAfterLoadFailure() {
        // Once the user adds media, the manifest is no longer empty and must be written.
        #expect(VideoProject.manifestSnapshot(manifest: sampleManifest(), loadFailed: true) != nil)
    }

    @Test func manifestSerializedNormallyWhenLoadSucceeded() {
        // Regression guard: ordinary saves still persist the (possibly empty) manifest.
        #expect(VideoProject.manifestSnapshot(manifest: MediaManifest(), loadFailed: false) != nil)
    }

    @Test func packageWriteCreatesMediaDirectory() throws {
        let bundle = try makeBundle()
        defer { try? fm.removeItem(at: bundle) }
        let snapshot = ProjectPackageSnapshot(
            timeline: try JSONEncoder().encode(Fixtures.timeline()),
            manifest: nil,
            thumbnail: nil,
            chatSessionFiles: []
        )

        try VideoProject.writeProjectPackage(snapshot, to: bundle, sourceURL: bundle)

        var isDirectory = ObjCBool(false)
        let mediaURL = bundle.appendingPathComponent(Project.mediaDirectoryName, isDirectory: true)
        #expect(fm.fileExists(atPath: mediaURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test func saveAsPreservesUnreadableManifestFile() throws {
        let source = try makeBundle()
        defer { try? fm.removeItem(at: source) }
        let original = Data("ORIGINAL-CORRUPT-MANIFEST-BYTES".utf8)
        try original.write(to: source.appendingPathComponent(Project.manifestFilename))

        let dest = fm.temporaryDirectory
            .appendingPathComponent("vp-dest-\(UUID().uuidString).metag", isDirectory: true)
        defer { try? fm.removeItem(at: dest) }

        let snapshot = ProjectPackageSnapshot(
            timeline: try JSONEncoder().encode(Fixtures.timeline()),
            manifest: nil,                    // unreadable on open → nothing to write
            thumbnail: nil,
            chatSessionFiles: []
        )

        try VideoProject.writeProjectPackage(snapshot, to: dest, sourceURL: source)

        #expect(fm.fileExists(atPath: dest.appendingPathComponent(Project.manifestFilename).path))
        let preserved = try Data(contentsOf: dest.appendingPathComponent(Project.manifestFilename))
        #expect(preserved == original)   // bytes carried over verbatim
    }

    @Test func inPlaceSaveLeavesUnreadableManifestUntouched() throws {
        // The common autosave path writes in place (source == dest). The original media.json
        // must survive byte-for-byte rather than being clobbered with an empty manifest.
        let bundle = try makeBundle()
        defer { try? fm.removeItem(at: bundle) }
        let original = Data("ORIGINAL-CORRUPT-MANIFEST-BYTES".utf8)
        try original.write(to: bundle.appendingPathComponent(Project.manifestFilename))

        let snapshot = ProjectPackageSnapshot(
            timeline: try JSONEncoder().encode(Fixtures.timeline()),
            manifest: nil,
            thumbnail: nil,
            chatSessionFiles: []
        )

        try VideoProject.writeProjectPackage(snapshot, to: bundle, sourceURL: bundle)

        let after = try Data(contentsOf: bundle.appendingPathComponent(Project.manifestFilename))
        #expect(after == original)
    }

    @MainActor
    @Test func emptyingTheLibraryPersistsOnceAManifestHasBeenRewritten() async throws {
        // After opening a corrupt-manifest project, rebuilding the library and saving writes a real
        // manifest. Emptying the library and saving again must persist as empty, not resurrect the
        // rebuilt entries from the no-longer-relevant load failure.
        let bundle = try makeBundle()
        defer { try? fm.removeItem(at: bundle) }
        try Data("{ corrupt ".utf8).write(to: bundle.appendingPathComponent(Project.manifestFilename))

        let doc = try await VideoProject.load(from: bundle)   // manifestLoadFailed = true

        doc.editorViewModel.mediaManifest = sampleManifest()
        try doc.write(to: bundle, ofType: VideoProject.typeIdentifier)
        #expect(try VideoProject.readProjectPackage(at: bundle).manifest?.entries.count == 1)

        doc.editorViewModel.mediaManifest = MediaManifest()
        try doc.write(to: bundle, ofType: VideoProject.typeIdentifier)

        let reopened = try VideoProject.readProjectPackage(at: bundle)
        #expect(reopened.manifest?.entries.isEmpty == true)   // emptied library sticks
        #expect(reopened.manifestUnreadable == false)         // valid (empty) manifest now
    }
}
