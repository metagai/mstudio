import Foundation
import Testing
@testable import PalmierPro

/// **他留下的是哪一部。**
///
/// 生产库里 1077 条导出记录，没有一条说得出被留下的是什么片子 ——
/// 于是「每一部合格的成本」这个指标没有分子。导出事件现在带上出片任务 id。
@Suite("导出要说出留下的是哪一部")
struct AcceptedFilmTests {
    private func resolver(_ pairs: [(ref: String, job: String?)]) -> MediaResolver {
        var manifest = MediaManifest()
        manifest.entries = pairs.map { pair in
            var entry = MediaManifestEntry(id: pair.ref, name: pair.ref, type: .video,
                                           source: .external(absolutePath: "/tmp/\(pair.ref).mp4"),
                                           duration: 3)
            if let job = pair.job {
                var input = GenerationInput(prompt: "", model: "local", duration: 3, aspectRatio: "16:9")
                input.backendJobId = job
                entry.generationInput = input
            }
            return entry
        }
        return MediaResolver(manifest: { manifest }, projectURL: { nil })
    }

    /// **一部片子十一镜，是一次验收，不是十一次。**
    @Test func itCountsOneFilmOnce() {
        let r = resolver([("a", "job-1"), ("b", "job-1"), ("c", "job-1")])
        #expect(FilmExportStats.films(of: ["a", "b", "c"], in: r) == ["job-1"])
    }

    /// 一条时间线可以拼进好几部片子，每一部都算数。
    @Test func itKeepsEveryFilmOnTheTimeline() {
        let r = resolver([("a", "job-2"), ("b", "job-1")])
        #expect(FilmExportStats.films(of: ["a", "b"], in: r) == ["job-1", "job-2"])
    }

    /// 自己拍的素材没有出片任务 —— 不许因此报一个空 id 进去。
    @Test func itIgnoresFootageWeDidNotGenerate() {
        let r = resolver([("a", nil), ("b", "")])
        #expect(FilmExportStats.films(of: ["a", "b"], in: r).isEmpty)
    }

    /// 时间线上没有一段是我们生成的 —— 这次导出没有可归属的片子。
    @Test func itSaysNothingWhenNothingWasGenerated() {
        #expect(FilmExportStats.films(of: [], in: resolver([])).isEmpty)
    }
}
