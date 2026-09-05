import SwiftUI

/// **他上一条片子，在首屏动着。**
///
/// 创始人 2026-08-10 点名：「最近的项目和 Template Lib 有待重新设计
/// （**交互不 Aha 是原罪**）」。todo 里那条判据是：
/// **一个刚回来的创作者，零点击就能看见自己上次做的东西。**
///
/// 2026-09-04 核实，Mac 在这条判据上是 0 分 —— 首页三块里没有一样是他自己的：
///
///     HomeHero              那句问话 + 三个起手式 + 样片（**别人的**）
///     SampleProjectsStrip   我们做的样例工程
///     MyProjectsSection     本地 .palmier 文件列表（**就是一个文件管理器**）
///
/// 他真正的片子在**编辑器的素材面板**里 —— 要先打开一个工程、进面板、切一个标签。
/// 而「创作者要的不是文件管理器，是接着上次那股劲」。
///
/// 所以这一格是**条件化的**，不是新加一块：
/// **他有片子就放他的最新那条，没有才放别人的样片。**
/// 那句问话照旧留着 —— 对第一次来的人，它仍然是对的主角。
@MainActor
struct LastFilm: View {
    let film: MetagGateway.FilmRow
    let onOpen: () -> Void

    var body: some View {
        // **不加标题。**
        //
        // 试过「接着上次那条」——那是一句新串，而 25 个语言各缺 360 句
        // （`untranslated-baseline.txt`），新加一句就是给它们再添一笔
        // 我读不了、验不了的欠账。`"My films"` 也在那笔欠账里，同样不能借。
        //
        // 而这一格本来就不需要标题：卡片底下写着**他自己那句话**，
        // 而他有片子的时候样片那一排已经被换掉了 ——
        // 屏幕上没有第二个"片子"可混淆。
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            MetagFilmCard(
                film: film,
                poster: nil,
                onOpen: onOpen,
                onShare: {},
                onDelete: {},
                autoplay: true
            )
            .frame(width: AppTheme.FilmWall.lastFilmWidth)
        }
    }

    /// 摆哪一条。**只摆打得开的那条** —— 一张点下去说"取不到了"的卡片，
    /// 比空着更糟：它把"接着上次那股劲"变成了一次失望。
    ///
    /// 纯函数，判据直接问它，不用起界面。
    nonisolated static func pick(_ films: [MetagGateway.FilmRow]) -> MetagGateway.FilmRow? {
        films.first { $0.retrievable && $0.status != "failed" && $0.poster != nil }
    }
}
