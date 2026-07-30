import Testing
import Foundation
@testable import PalmierPro

/// 边好边填依赖网关回的 `shots_done`。这一条守的是**静默退化**：
/// 字段一旦改名或消失，解码得到 nil、进度恒为 0，出片会退回"等全片才铺"——
/// 不报错、不崩溃，只是用户又要多等几分钟，而没有任何地方会告诉我们。
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

    /// 老任务、或将来某个不回这个字段的端点，都不该让解码整个失败 ——
    /// 拿不到进度只是少一个优化，拿不到任务是功能没了。
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
