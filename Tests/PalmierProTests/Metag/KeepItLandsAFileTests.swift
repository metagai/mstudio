import AVFoundation
import Foundation
import Testing
@testable import PalmierPro

/// **「留下它」按下去，磁盘上真的多一个能播的文件。**
///
/// `KeepItTests` 只证明了文件名算得对。而那颗按钮在北极星那条路上
/// （`exported` = 0，从来没人把片子带走），**在这条路上发一个没跑通的
/// 保存按钮，等于把那个 0 焊死。**
///
/// 走的是和界面同一条路：`ExportQueue.enqueueVideo` + `.keepIt` 的那两个
/// 默认值（H.264 / 跟随时间线）。**不另起一条**，否则测的就不是他按下去
/// 会发生的事。慢（真跑一次 AVFoundation 导出，~1–2s）。
@Suite("留下它真的落下一个文件", .serialized)
@MainActor
struct KeepItLandsAFileTests {

    @Test func pressingKeepItPutsAPlayableFilmOnDisk() async throws {
        let renderSize = CGSize(width: 320, height: 180)
        let blackURL = try await ImageVideoGenerator.blackVideo(size: renderSize)

        let mediaRef = "keepit-fixture"
        var manifest = MediaManifest()
        manifest.entries = [MediaManifestEntry(
            id: mediaRef, name: "black", type: .video,
            source: .external(absolutePath: blackURL.path), duration: 5.0
        )]
        let resolver = MediaResolver(manifest: { manifest }, projectURL: { nil })

        let clip = Fixtures.clip(id: "c1", mediaRef: mediaRef, start: 0, duration: 30)
        var timeline = Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [clip])])
        timeline.width = Int(renderSize.width)
        timeline.height = Int(renderSize.height)

        // 他那句话当片名 —— 带着斜杠和引号，正是 `sanitized` 要挡的那种。
        timeline.name = "夜里/东京 雨中：一个\"快递员\""

        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keepit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let outURL = KeepIt.destination(
            name: timeline.name, ext: ExportFormat.h264.fileExtension,
            in: folder, exists: { FileManager.default.fileExists(atPath: $0.path) }
        )

        let submission = try ExportQueue.shared.enqueueVideo(
            timeline: timeline,
            resolver: resolver,
            resolveTimeline: { _ in nil },
            format: .h264,
            resolution: .matchTimeline,
            missingMediaRefs: [],
            outputURL: outURL,
            source: .keepIt,
            projectID: "keepit-test-\(UUID().uuidString)",
            analyticsProjectID: nil
        )
        _ = submission

        try await AsyncWait.until("导出落地", timeout: .seconds(60)) {
            FileManager.default.fileExists(atPath: outURL.path)
        }

        // **能播才算留下来。** 一个 0 字节的文件在访达里看起来一切正常。
        let asset = AVURLAsset(url: outURL)
        let duration = try await asset.load(.duration)
        #expect(duration.seconds > 0, "文件在，但它不是一条片子")
        let tracks = try await asset.loadTracks(withMediaType: .video)
        #expect(!tracks.isEmpty, "没有视频轨 —— 他打开会看到一片黑")
    }
}
