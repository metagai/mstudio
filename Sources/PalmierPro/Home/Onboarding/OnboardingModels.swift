import Foundation

enum OnboardingStep: Int {
    case welcome, profile, account
}

enum OnboardingSampleState: Equatable {
    case idle
    case loading
    case failed
}

struct OnboardingOption: Identifiable {
    let id: String
    /// **存 key，不存已本地化的字符串。**
    /// 在类型初始化时本地化会让切换语言不生效（静态常量只算一次），
    /// 而且静态上下文拿不到主 actor 隔离的 L(...)。渲染处才调 L()。
    let labelKey: String
    static let other = OnboardingOption(id: "other", labelKey: "Other")
}

enum OnboardingQuestion: String, CaseIterable, Identifiable {
    case roles, videoTypes, interests
    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .videoTypes: "What do you make?"
        case .roles: "What best describes your role?"
        case .interests: "What interests you most about METAG?"
        }
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
        }
    }
}
