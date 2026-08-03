import Foundation

/// 旁白音色。
///
/// 网关只回一个 id（`warm_female`），**界面上那句「温暖 · 故事女声」在这里** ——
/// 机器契约里不放本地化文案。id 的出处是 workers/narrator.py 的 VOICES。
///
/// 此前所有片子共用一个写死的音色（龙小淳，官方分类是「语音助手」），
/// 于是悬疑片配客服音。现在由模型按内容选，用户不同意就一下换掉：
/// 不收费、不重画首帧、几秒就听到。
enum MetagNarrator: String, CaseIterable, Sendable {
    case cinematicMale = "cinematic_male"
    case authoritativeMale = "authoritative_male"
    case energeticMale = "energetic_male"
    case warmFemale = "warm_female"
    case intimateFemale = "intimate_female"

    /// 「感觉 · 是谁在说」两段：用户挑的是感觉，认的是声音。
    func displayName(for lang: String) -> String {
        switch (self, lang) {
        case (.cinematicMale, "zh"): return "电影感 · 沉稳男声"
        case (.cinematicMale, "es"): return "Cinematográfica — voz grave"
        case (.cinematicMale, _): return "Cinematic — deep male"
        case (.authoritativeMale, "zh"): return "纪录片 · 播报男声"
        case (.authoritativeMale, "es"): return "Documental — locutor"
        case (.authoritativeMale, _): return "Documentary — anchor male"
        case (.energeticMale, "zh"): return "明快 · 活力男声"
        case (.energeticMale, "es"): return "Enérgica — voz vibrante"
        case (.energeticMale, _): return "Energetic — bright male"
        case (.warmFemale, "zh"): return "温暖 · 故事女声"
        case (.warmFemale, "es"): return "Cálida — narradora"
        case (.warmFemale, _): return "Warm — storyteller female"
        case (.intimateFemale, "zh"): return "轻柔 · 独白女声"
        case (.intimateFemale, "es"): return "Íntima — voz suave"
        case (.intimateFemale, _): return "Intimate — soft female"
        }
    }
}
