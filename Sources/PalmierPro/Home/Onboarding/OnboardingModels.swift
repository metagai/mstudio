import Foundation

enum OnboardingStep: Int {
    case welcome, discovery, profile, account
}

enum OnboardingSampleState: Equatable {
    case idle
    case loading
    case failed
}

struct OnboardingOption: Identifiable {
    let id: String
    /// **裸 key，不是已本地化的字符串。** 这些选项存在 static let 里，
    /// 在类型初始化时本地化只会算一次 —— 用户切语言，选项不会跟着变。
    /// 渲染处用 `L10n.string(key:)` 解析。
    let labelKey: String
    static let other = OnboardingOption(id: "other", labelKey: "Other")
}

enum OnboardingQuestion: String, CaseIterable, Identifiable {
    case roles, videoTypes, interests, acquisitionSource, previousEditors

    var id: String { rawValue }

    static let profileQuestions: [OnboardingQuestion] = [.roles, .videoTypes, .interests]
    static let discoveryQuestions: [OnboardingQuestion] = [.acquisitionSource, .previousEditors]

    var titleKey: String {
        switch self {
        case .videoTypes: L10n.key("What do you make?")
        case .roles: L10n.key("What best describes your role?")
        case .interests: L10n.key("What interests you most about METAG?")
        case .acquisitionSource: L10n.key("How did you find METAG?")
        case .previousEditors: L10n.key("Which editors did you use before?")
        }
    }

    var allowsMultipleSelection: Bool {
        self != .acquisitionSource
    }

    var exclusiveOptionIDs: Set<String> {
        self == .previousEditors ? ["none"] : []
    }

    var options: [OnboardingOption] {
        switch self {
        case .videoTypes: [
            .init(id: "short_form", labelKey: "Short-form and social"),
            .init(id: "youtube", labelKey: "YouTube"),
            .init(id: "podcast", labelKey: "Podcast"),
            .init(id: "ai_videos", labelKey: "AI videos"),
            .init(id: "advertising", labelKey: "Ads and branded content"),
            .init(id: "product_demos", labelKey: "Product demos"),
            .init(id: "education", labelKey: "Education and tutorials"),
            .other,
        ]
        case .roles: [
            .init(id: "editor", labelKey: "Video editor"),
            .init(id: "filmmaker", labelKey: "Filmmaker"),
            .init(id: "hobbyist", labelKey: "Hobbyist"),
            .init(id: "founder", labelKey: "Founder"),
            .init(id: "designer", labelKey: "Designer"),
            .init(id: "content_creator", labelKey: "Content creator"),
            .init(id: "student", labelKey: "Student"),
            .init(id: "marketer", labelKey: "Marketer"),
            .other,
        ]
        case .interests: [
            .init(id: "ai_generation", labelKey: "AI videos"),
            .init(id: "ai_transcription", labelKey: "AI transcription"),
            .init(id: "agent_editing", labelKey: "Agentic editing"),
            .init(id: "external_agents", labelKey: "Integration with your own agent"),
            .init(id: "video_automation", labelKey: "Video automation"),
        ]
        case .acquisitionSource: [
            .init(id: "google", labelKey: "Google"),
            .init(id: "github", labelKey: "GitHub"),
            .init(id: "x", labelKey: "X"),
            .init(id: "instagram", labelKey: "Instagram"),
            .init(id: "youtube", labelKey: "YouTube"),
            .init(id: "hacker_news", labelKey: "Hacker News"),
            .init(id: "word_of_mouth", labelKey: "Friend or colleague"),
            .other,
        ]
        case .previousEditors: [
            .init(id: "premiere_pro", labelKey: "Adobe Premiere Pro"),
            .init(id: "davinci_resolve", labelKey: "DaVinci Resolve"),
            .init(id: "final_cut_pro", labelKey: "Final Cut Pro"),
            .init(id: "capcut", labelKey: "CapCut"),
            .init(id: "instagram_edits", labelKey: "Instagram Edits"),
            .init(id: "imovie", labelKey: "iMovie"),
            .init(id: "descript", labelKey: "Descript"),
            .init(id: "none", labelKey: "None"),
            .other,
        ]
        }
    }
}
