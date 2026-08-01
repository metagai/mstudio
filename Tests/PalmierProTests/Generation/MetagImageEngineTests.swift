import Testing
@testable import PalmierPro

/// 带了图却选了吃不下图的档，必须在扣费之前说清楚。
///
/// 起因（web 端用户反馈）："上传了人像，生成后和自己无关"。
/// 查下来引擎其实会用首帧，问题在于**不是所有档都吃图**：
/// seedance / veo / cloud 的提交体里只有 prompt，图被静默丢弃，
/// 而用户按 26~60 credits/镜已经付过了。
///
/// 网关也会 400 拦一次；客户端先拦是为了给出**能读懂的原因**，而不是一个状态码。
@Suite("图生视频的引擎适配")
struct MetagImageEngineTests {
    private func engine(_ id: String, accepts: Bool?) -> MetagGateway.Pricing.Engine {
        .init(id: id, name: id, name_i18n: nil, spec: "", resolution: nil,
              duration_s: nil, native_audio: false, credits_per_shot: 1,
              accepts_image: accepts)
    }

    @Test("网关明说不吃图时，acceptsImage 为假")
    func rejects() {
        #expect(engine("seedance", accepts: false).acceptsImage == false)
    }

    @Test("老网关不回这个字段时按可用处理 —— 宁可让网关去拦，也不要误挡住可用的档")
    func defaultsToTrue() {
        #expect(engine("local", accepts: nil).acceptsImage == true)
    }

    @Test("报错文案要说清楚换哪一档，而不是只说不行")
    func errorTellsWhatToDo() {
        let msg = BackendError.imageNotSupported(engine: "Seedance").errorDescription ?? ""
        #expect(msg.contains("Seedance"))
        #expect(msg.contains("标准") || msg.contains("Grok"))
    }
}
