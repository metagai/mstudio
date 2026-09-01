import Foundation
import Testing
@testable import PalmierPro

/// 报价的形状是**跨仓库契约**（gateway/src/director.rs 的 `quote_for`）。
/// 网关改了字段名，Mac 这边解不出来 —— 而失败是静默的：`try?` 吞掉之后
/// 界面上只是那句"要花多少"不出现，没有任何报错。所以这几条盯着解码本身。
@Suite("出片报价")
struct MetagQuoteTests {
    /// 网关真实回包的形状（`director.rs` 里 `out` 那个 json!）。
    private static let payload = """
    {
      "topic": "a cat in a laundromat",
      "shots": 4,
      "storyboard": {"video_prompts": ["a", "b"]},
      "options": [
        {"engine": "local", "spec": "480P · 5s", "credits_per_shot": 1, "total_credits": 4},
        {"engine": "seedance", "spec": "720P · 5s", "credits_per_shot": 26, "total_credits": 104}
      ],
      "recommended": {"engine": "seedance", "spec": "720P · 5s", "credits_per_shot": 26, "total_credits": 104},
      "recommended_why": "Best value per second at this quality.",
      "recommended_why_i18n": {"en": "Best value per second.", "zh": "每秒最划算。"},
      "charged": 0,
      "cached": false
    }
    """

    private func decoded() throws -> MetagGateway.Quote {
        try JSONDecoder().decode(MetagGateway.Quote.self, from: Data(Self.payload.utf8))
    }

    @Test func decodesTheGatewayShape() throws {
        let q = try decoded()
        #expect(q.shots == 4)
        #expect(q.options.count == 2)
        #expect(q.recommended?.engine == "seedance")
        #expect(q.recommended?.total_credits == 104)
    }

    /// 总价必须是网关算的那一个，不是我们再乘一遍 ——
    /// 网关改档位价格时，本地那份会照旧报旧价而用户扣的是新价。
    @Test func totalComesFromTheGatewayNotLocalMath() throws {
        let q = try decoded()
        for option in q.options {
            #expect(option.total_credits == option.credits_per_shot * q.shots)
        }
    }

    @Test func whyFollowsTheLanguageAndFallsBackToEnglish() throws {
        let q = try decoded()
        #expect(q.why("zh") == "每秒最划算。")
        #expect(q.why("en") == "Best value per second.")
        // 没有西语就回落英文 —— 空着比显示一个键名好，但英文比空着好。
        #expect(q.why("es") == "Best value per second.")
    }

    /// 网关可能不推荐任何一档（全都停售、或分镜看不出偏好）。
    /// **那时不推荐，也不编一个** —— 界面上那句话直接不出现。
    @Test func recommendationIsOptional() throws {
        let json = Self.payload
            .replacingOccurrences(of: "\"recommended\": {\"engine\": \"seedance\", \"spec\": \"720P · 5s\", \"credits_per_shot\": 26, \"total_credits\": 104}",
                                  with: "\"recommended\": null")
        let q = try JSONDecoder().decode(MetagGateway.Quote.self, from: Data(json.utf8))
        #expect(q.recommended == nil)
        #expect(!q.options.isEmpty, "没有推荐档不等于没有档位可选")
    }

    /// 理由整块缺失也要解得出来 —— 老网关不回这个字段。
    @Test func missingReasonStillDecodes() throws {
        let json = Self.payload.replacingOccurrences(
            of: "\"recommended_why_i18n\": {\"en\": \"Best value per second.\", \"zh\": \"每秒最划算。\"},",
            with: ""
        )
        let q = try JSONDecoder().decode(MetagGateway.Quote.self, from: Data(json.utf8))
        #expect(q.why("en") == nil)
        #expect(q.recommended?.total_credits == 104)
    }
}
