import Foundation

/// 引导页的顺序。**翻页完全由这里的 raw value 决定**（`move(by:)`），
/// 所以改顺序就是改这一行。
///
/// 原来是 `welcome → discovery → profile → account`：一个刚装完、
/// 什么都还没看到的人，要先答完**两屏问卷**，才走到"看你的片子"那一步。
///
/// 8/29 起 1112 个人落地、**0 个人打过一行字**。在人看到价值之前问他是做什么的，
/// 得到的就是 0 —— 而这两屏正好站在价值前面。
///
/// 现在看片排在问卷前面。真正的效果是：**愿意动手的人一屏问卷都不会看到**
/// （"先看一眼"和登录都直接结束引导），问卷只留给那些看完介绍就是不动手的人。
/// 而那恰恰是"你从哪儿知道我们"最该问的一群 —— 他们来了又要走。
/// 引导的四步曾经是 `welcome → account → discovery → profile`。
///
/// **`welcome` 删了。** 它是一张盖住首屏的卡片，上面写着
/// 「欢迎使用 METAG」+ 一张图库蝴蝶照 + **和首屏一字不差的同一句话**
/// （两处用的是同一个 `L10n.string(...)`），底下一颗「继续」。
///
/// 也就是说：新用户看到的第一样东西，是一张**挡住产品、重复被它挡住那句话**
/// 的卡片。而它盖住的那一屏现在有三条点开就能播的真片子。
enum OnboardingStep: Int {
    case account, discovery, profile
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
