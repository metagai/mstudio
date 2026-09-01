import SwiftUI

/// 为这一次创作组建的班底。**和 studio 是同一批人**
/// （`studio/apps/web/src/services/metag/crew.ts`）—— 同一个团队在两个产品里
/// 不该是两组名字。
///
/// ## 它必须是真的，否则就是最坏的一种装饰
///
/// 这条流水线本来就有这些工种，一个不多一个不少。**每个人到位的时刻，
/// 是那一阶段真的开始的时刻 —— 不是定时器。** 一个按秒数假装干活的团队，
/// 等到片子卡住时还在欢快推进，那一刻用户会明白刚才那两分钟全是演的。
/// 演砸的仪式比没有仪式更伤。
///
/// studio 那边为此栽过一次：第一版把导演挂在 `review` 上，查 `cpu_worker`
/// 才发现草案压根不跑 review（导演回看是交付后台跑的，实测 114 秒）——
/// 照那版发出去，用户会看到一个全程暗着、从不干活的导演。
enum MetagCrew {
    /// 流水线的真实顺序。用来判断某人是「还没轮到」还是「已经交活」。
    /// `review` 不在这里，理由见上。
    static let stageOrder = ["storyboard", "voice", "narration", "frames", "compose", "music"]

    struct Member: Identifiable, Sendable {
        /// 网关真报的那个阶段名。
        let stage: String
        /// 名字。**人有名字，工具没有** —— 这是「团队」和「进度条」的分界线。
        let name: String
        let title: String
        /// 正在做的这件事，一句话。
        let doing: String
        /// 他从上一位手里接过什么。**带真实数字。**
        /// 协作是在交接那一瞬间被感知的；只是轮流亮灯，看起来还是各干各的六个人。
        /// `%@` 处填上一段真的产出数。第一位没有上家。
        let tookOver: String?
        /// 徽章色。取自 studio 那份班底的 `wear`，三端同一个人同一个颜色。
        let tint: Color

        var id: String { stage }
        /// 名字首字母。通告单上的写法，不画脸 —— 纸感界面里卡通脸会掉价。
        var monogram: String { String(name.prefix(1)) }
    }

    static let members: [Member] = [
        // 导演占 storyboard 而不是单开一格：把一句话拆成一场场戏，
        // 正是导演在做的事，而那一段也是最长的一段（约占整段等待的四成）。
        Member(stage: "storyboard", name: "Nova", title: L10n.key("Director"),
               doing: L10n.key("Breaking your line into shots"),
               tookOver: nil, tint: Color(red: 0.298, green: 0.431, blue: 0.961)),
        Member(stage: "voice", name: "Kai", title: L10n.key("Casting"),
               doing: L10n.key("Finding the right voice"),
               tookOver: L10n.key("Nova handed me %@ shots. Finding who should read them."),
               tint: Color(red: 0.878, green: 0.537, blue: 0.290)),
        Member(stage: "narration", name: "Iris", title: L10n.key("Voice actor"),
               doing: L10n.key("Recording the narration"),
               tookOver: L10n.key("Kai picked the voice. Reading Nova's %@ lines now."),
               tint: Color(red: 0.847, green: 0.333, blue: 0.435)),
        Member(stage: "frames", name: "Ren", title: L10n.key("Cinematographer"),
               doing: L10n.key("Lining up the first frame"),
               tookOver: L10n.key("Working from Nova's shot list — %@ frames to light."),
               tint: Color(red: 0.227, green: 0.635, blue: 0.627)),
        Member(stage: "compose", name: "Bo", title: L10n.key("Editor"),
               doing: L10n.key("Cutting it together"),
               tookOver: L10n.key("All %@ shots are in. Cutting them together."),
               tint: Color(red: 0.420, green: 0.447, blue: 0.502)),
        Member(stage: "music", name: "Lu", title: L10n.key("Composer"),
               doing: L10n.key("Scoring it"),
               tookOver: L10n.key("The cut is locked. Writing something to carry it."),
               tint: Color(red: 0.545, green: 0.361, blue: 0.965)),
    ]

    enum Standing: Equatable {
        /// 还没轮到 —— 已经到场，但没开工。
        case waiting
        /// 正在干活。
        case working
        /// 交活了。
        case done
    }

    /// 某人此刻的状态。**只由 `stage` 决定**，没有任何时间参与。
    ///
    /// 网关还没报阶段（刚提交、或老网关）时，一律 `waiting` —— 宁可一个人
    /// 都不亮，也不要亮一个其实没在干活的。
    static func standing(of member: Member, stage: String?) -> Standing {
        guard let stage, let now = stageOrder.firstIndex(of: stage),
              let mine = stageOrder.firstIndex(of: member.stage)
        else { return .waiting }
        if mine < now { return .done }
        return mine == now ? .working : .waiting
    }

    /// 正在干活的那位。
    static func current(stage: String?) -> Member? {
        members.first { standing(of: $0, stage: stage) == .working }
    }
}

extension Int {
    /// 0 当作"还不知道" —— 交接句里不该出现"handed me 0 shots"。
    var nonZero: Int? { self > 0 ? self : nil }
}
