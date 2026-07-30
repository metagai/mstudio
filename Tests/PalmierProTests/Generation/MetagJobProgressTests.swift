import Testing
import Foundation
@testable import PalmierPro

/// If `shots_done` is ever renamed it decodes to nil and progress silently reverts to all-at-once.
@Suite("METAG job — 出片进度")
struct MetagJobProgressTests {

    private func decode(_ json: String) throws -> MetagGateway.Job {
        try JSONDecoder().decode(MetagGateway.Job.self, from: Data(json.utf8))
    }

    @Test("shots_done 按线上字段名解出来")
    func decodesShotsDone() throws {
        let job = try decode("""
        {"job_id":"j1","status":"generating","error":null,"cover":null,"shots_done":3,
         "shots":[{"narration":"a","video":"shot_0.mp4","audio":"shot_0.wav"},
                  {"narration":"b","video":"shot_1.mp4","audio":"shot_1.wav"}]}
        """)
        #expect(job.shots_done == 3)
        #expect(job.status == "generating")
    }

    @Test("字段缺失时降级为 nil，而不是解码失败")
    func toleratesMissingField() throws {
        let job = try decode("""
        {"job_id":"j1","status":"done","error":null,"cover":null,"shots":[]}
        """)
        #expect(job.shots_done == nil)
        #expect(job.job_id == "j1")
    }

    @Test("readyCount 缺省为 0，不会凭空认为有镜头可取")
    func readyCountDefaultsToZero() {
        let j = BackendGenerationJob(
            _id: "j1", status: .running, resultUrls: ["a", "b"],
            errorMessage: nil, costCredits: nil, completedAt: nil
        )
        #expect(j.readyCount == 0)
    }
}
