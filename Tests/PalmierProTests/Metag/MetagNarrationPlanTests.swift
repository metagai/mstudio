import Foundation
import Testing

@testable import PalmierPro

/// 原生出声的档位不该再收一条 TTS 旁白，无声的档位一条都不能少。
///
/// 判据来自 `/api/v1/pricing` 的 `native_audio`。这里**故意用一张假的报价单**，
/// 而不是硬编 seedance/veo 的名字 —— 测的是"跟着报价单走"，
/// 不是"我们今天记得哪几档会说话"。
struct MetagNarrationPlanTests {

    private func pricing(_ engines: [(String, Bool)]) -> MetagGateway.Pricing {
        MetagGateway.Pricing(
            signup_free_credits: 20,
            plans: [],
            engines: engines.map { id, native in
                MetagGateway.Pricing.Engine(
                    id: id, name: id, name_i18n: nil, spec: "", resolution: nil,
                    duration_s: nil, native_audio: native, credits_per_shot: 1
                )
            }
        )
    }

    private var live: Set<String> {
        MetagNarrationPlan.nativeAudioEngineIds(
            pricing([("local", false), ("cloud", false), ("seedance", true), ("veo", true)])
        )
    }

    @Test func nativeAudioShotsGetNoNarration() {
        #expect(MetagNarrationPlan.shotsNeedingNarration(
            shots: 3, shotEngines: ["seedance", "veo", "seedance"], nativeAudioEngineIds: live
        ) == [])
    }

    @Test func silentEngineShotsAlwaysGetNarration() {
        #expect(MetagNarrationPlan.shotsNeedingNarration(
            shots: 3, shotEngines: ["local", "cloud", "local"], nativeAudioEngineIds: live
        ) == [0, 1, 2])
    }

    /// 混档的片子逐镜判。整片一刀切会让无声档的那几镜变哑。
    @Test func mixedFilmSkipsOnlyTheNativeShots() {
        #expect(MetagNarrationPlan.shotsNeedingNarration(
            shots: 4, shotEngines: ["local", "veo", "local", "seedance"], nativeAudioEngineIds: live
        ) == [0, 2])
    }

    /// 引擎表是新增的字段。**取不到时一镜都不跳** ——
    /// 两种错的代价不对称：多一条旁白用户可以删，少一条他拿到的是哑片。
    @Test(arguments: [nil, []] as [[String?]?])
    func missingShotEnginesFallBackToNarratingEverything(engines: [String?]?) {
        #expect(MetagNarrationPlan.shotsNeedingNarration(
            shots: 2, shotEngines: engines, nativeAudioEngineIds: live
        ) == [0, 1])
    }

    /// 报价单取不到也一样：空集意味着"我不知道哪档会说话"，不是"都不会说话"。
    @Test func missingPricingNarratesEverything() {
        #expect(MetagNarrationPlan.shotsNeedingNarration(
            shots: 2, shotEngines: ["seedance", "veo"],
            nativeAudioEngineIds: MetagNarrationPlan.nativeAudioEngineIds(nil)
        ) == [0, 1])
    }

    /// 数组短了是缺数据，不是"其余都是原生的"。
    @Test func shortOrNilEntriesCountAsNeedingNarration() {
        #expect(MetagNarrationPlan.shotsNeedingNarration(
            shots: 4, shotEngines: ["seedance", nil], nativeAudioEngineIds: live
        ) == [1, 2, 3])
    }

    /// 认不出的档位名（网关加了新档而客户端的报价单还是旧的）按要旁白处理。
    @Test func unknownEngineNamesNarrate() {
        #expect(MetagNarrationPlan.shotsNeedingNarration(
            shots: 1, shotEngines: ["brand-new-tier"], nativeAudioEngineIds: live
        ) == [0])
    }

    @Test func doneFilmsOpenEveryShot() {
        #expect(MetagNarrationPlan.shotsToOpen(shots: 3, status: "done", salvaged: nil) == [0, 1, 2])
    }

    /// 整单失败但有抢救出来的镜头：只开那几镜，其余是必然 404 的下载。
    @Test func failedFilmsOpenOnlyTheSalvagedShots() {
        #expect(MetagNarrationPlan.shotsToOpen(shots: 4, status: "failed", salvaged: [2, 0]) == [0, 2])
    }

    /// 服务端给的镜号不保证干净：重复要去掉，越界的不能拿去下标数组。
    @Test func salvagedIndicesAreDeduplicatedAndBoundsChecked() {
        #expect(MetagNarrationPlan.shotsToOpen(shots: 3, status: "failed", salvaged: [1, 1, 9, -1]) == [1])
    }

    /// 没有 salvaged 的失败单一镜都不开 —— 不去下载一批必然 404 的文件。
    @Test func failedFilmsWithoutSalvageOpenNothing() {
        #expect(MetagNarrationPlan.shotsToOpen(shots: 3, status: "failed", salvaged: nil) == [])
    }
}

/// 多出来的字段不能让整个任务解析不出来。
///
/// `salvaged` / `shot_engines` / `refunded` 是网关新加的。**老客户端见到它们必须照常工作** ——
/// 一个因为多了一个字段就打不开的列表，比没有这个字段更糟。
struct MetagJobDecodingTests {

    private func job(_ json: String) throws -> MetagGateway.Job {
        try JSONDecoder().decode(MetagGateway.Job.self, from: Data(json.utf8))
    }

    @Test func decodesTheNewFailureFields() throws {
        let j = try job("""
        {"job_id":"j","status":"failed","error":"gate","shots":[
          {"narration":"a","video":"shot_0.mp4","audio":"shot_0.wav"},
          {"narration":"b","video":"shot_1.mp4","audio":"shot_1.wav"}],
         "cover":null,"salvaged":[0],"refunded":true,"shot_engines":["veo","local"]}
        """)
        #expect(j.salvaged == [0])
        #expect(j.refunded == true)
        #expect(j.shot_engines?.compactMap { $0 } == ["veo", "local"])
    }

    /// 反过来也要成立：老网关不回这几个字段时不能解析失败。
    @Test func decodesWithoutTheNewFields() throws {
        let j = try job("""
        {"job_id":"j","status":"done","error":null,"cover":null,
         "shots":[{"narration":"a","video":"shot_0.mp4","audio":"shot_0.wav"}]}
        """)
        #expect(j.salvaged == nil)
        #expect(j.refunded == nil)
        #expect(j.shot_engines == nil)
    }

    /// 未知字段不能让解码报错 —— 这是"至少不要因为多了一个字段而解析出错"的判据本身。
    @Test func unknownFieldsAreIgnored() throws {
        let j = try job("""
        {"job_id":"j","status":"done","error":null,"cover":null,"shots":[],
         "some_field_invented_next_week":{"a":[1,2,3]}}
        """)
        #expect(j.job_id == "j")
    }
}
