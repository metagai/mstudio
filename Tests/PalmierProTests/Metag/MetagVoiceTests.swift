import Foundation
import Testing

@testable import PalmierPro

/// 声音复刻的硬约束。
///
/// 音色属人身权：网关要求 consent 为 true，否则 403 并记录来源 IP。
/// 界面上那个勾**不许预勾选，也不许由「继续」隐含** —— 它是一次授权，不是一个偏好。
/// 这不是审美问题，坏了是拿别人的声音去复刻。
struct VoiceCloneFormTests {
    private let sample = URL(fileURLWithPath: "/tmp/sample.wav")

    @Test func consentStartsUnchecked() {
        #expect(VoiceCloneForm().consent == false)
    }

    @Test func everyConditionIsRequired() {
        var f = VoiceCloneForm(sample: sample, name: "我的声音", consent: true)
        #expect(f.isReady)

        f.consent = false
        #expect(!f.isReady, "没有授权就不能复刻")

        f = VoiceCloneForm(sample: nil, name: "我的声音", consent: true)
        #expect(!f.isReady, "没有样本就不能复刻")

        f = VoiceCloneForm(sample: sample, name: "   ", consent: true)
        #expect(!f.isReady, "只有空白的名字不算名字")
    }

    /// 上一次的授权不适用于下一段样本。
    @Test func resetClearsConsentToo() {
        var f = VoiceCloneForm(sample: sample, name: "我的声音", consent: true)
        f.reset()
        #expect(f == VoiceCloneForm())
        #expect(f.consent == false)
    }
}

struct MetagVoiceGatewayTests {
    /// 扩展名跟着实际内容走。拿 WAV 当 .mp3 存，AVFoundation 会拒绝它，
    /// 而用户看到的是"配音失败" —— 与真正的失败无从区分，也就无从排查。
    @Test func audioExtensionFollowsTheBytes() {
        #expect(MetagGateway.audioExtension(for: Data("RIFF....WAVEfmt ".utf8)) == "wav")
        #expect(MetagGateway.audioExtension(for: Data([0xFF, 0xFB, 0x90, 0x00])) == "mp3")
        #expect(MetagGateway.audioExtension(for: Data()) == "mp3", "认不出来时按 mp3，不要崩")
    }

    /// 复刻单价来自网关。写死的数字迟早和账单对不上 —— 引导页那次就是照抄上游的
    /// "250 free credits"，而我们给 20。
    @Test func pricingCarriesExtras() throws {
        let json = """
        {"signup_free_credits":20,"plans":[],"engines":[],
         "extras":{"voice_clone":50,"image_edit":4}}
        """
        let p = try JSONDecoder().decode(MetagGateway.Pricing.self, from: Data(json.utf8))
        #expect(p.extras?["voice_clone"] == 50)
    }

    /// 老网关不回 extras 时，整份定价仍要解得出来 —— 否则一次回滚会让
    /// 所有档位从界面上消失。
    @Test func pricingSurvivesAGatewayWithoutExtras() throws {
        let json = #"{"signup_free_credits":20,"plans":[],"engines":[]}"#
        let p = try JSONDecoder().decode(MetagGateway.Pricing.self, from: Data(json.utf8))
        #expect(p.extras == nil)
        #expect(p.signup_free_credits == 20)
    }
}
