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

    /// 这句话要说清楚**是哪一档不行**，但**不许点名"那就选 X"**。
    ///
    /// 上一版写的是「标准（自研）」或 Grok。后来 grok 停售、wan-flash 上架，
    /// 这句话就开始把用户指向一档他买不到的模型 —— 而它当时是绿的，
    /// 因为测试断言的正是那两个写死的名字。
    /// 收不收图的真相在报价单的 `accepts_image` 里，选择器已经据此禁用了。
    @Test("报错要点名是哪一档不行，但不许点名替代档 —— 那种名单必然过期")
    func namesTheEngineButNotAReplacement() {
        let msg = BackendError.imageNotSupported(engine: "Seedance").errorDescription ?? ""
        #expect(msg.contains("Seedance"))
        for staleName in ["Grok", "grok", "wan-flash", "seedance-25", "Veo", "标准"] {
            #expect(!msg.contains(staleName), "文案里点了 \(staleName) 的名，这份名单会过期")
        }
    }
}
