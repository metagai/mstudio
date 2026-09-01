import SwiftUI

/// 等待时的那块幕布：**他的片子在他眼前一格一格填起来。**
///
/// ## 为什么不是一排缩略图
///
/// 原来这里是 84×48 的一排小图，有几张摆几张 —— 于是那 90 秒里，
/// 屏幕上只有"零张、一张、两张"，**他看不出这条片子有多长、还差多少**。
/// 一排会变多的邮票，讲不出"我的片子正在成形"这件事。
///
/// 现在先按真实镜数摆好空格，每一格填进来都是**一次真的到货**
/// （`first_frames` 轮询回来一张，就填一格）。他看到的是一张逐渐完整的
/// 场记板 —— 而那正是这一刻唯一值得看的东西。
///
/// ## 仪式必须是真的
///
/// 这一块和班底（`MetagCrew`）守同一条规矩：**没有任何动画由定时器驱动。**
/// 空格数 = 网关报的镜数，填格 = 那一张真的下载完了，最后那一下"落定"
/// = 最后一格真的到齐。
///
/// 一个按秒数假装进度的幕布，在片子卡住时还会欢快地拉开 ——
/// 那一刻用户会明白刚才全是演的。**演砸的仪式比没有仪式更伤。**
struct MetagFilmStrip: View {
    /// 网关报的镜数。拿不到就按已到的张数摆 —— 不虚构格子。
    let shots: Int
    let frames: [Int: NSImage]

    /// 全到齐了。最后那一下落定挂在它上面。
    private var complete: Bool { shots > 0 && frames.count >= shots }

    /// 摆几格。**不虚构格子** —— 网关报了镜数就按它，报不上来就按已到的张数。
    private var slots: Int { max(shots, frames.keys.map { $0 + 1 }.max() ?? 0) }

    // 判据要能问到这两个数，而它们是这块幕布"说的是不是真话"的全部内容。
    var slotCountForTesting: Int { slots }
    var completeForTesting: Bool { complete }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(
                .adaptive(minimum: AppTheme.MetagDraft.stripCellWidth),
                spacing: AppTheme.Spacing.xs
            )],
            spacing: AppTheme.Spacing.xs
        ) {
            ForEach(0..<slots, id: \.self) { i in
                cell(at: i)
            }
        }
        // 到齐的那一下：整块轻轻落定一次。**只有一下**，
        // 而且挂在"最后一格真的到了"上，不是挂在秒数上。
        .scaleEffect(complete ? 1 : 0.995)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: complete)
    }

    @ViewBuilder
    private func cell(at index: Int) -> some View {
        let image = frames[index]
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // 还没到的那一格：**安静地占着位**。
                // 不放转圈、不放骨架闪光 —— 一直在动的东西会把注意力
                // 从已经到了的画面上拽走，而那才是他想看的。
                AppTheme.Background.baseColor
                Text(verbatim: "\(index + 1)")
                    .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(AppTheme.Text.mutedColor)
                    .monospacedDigit()
            }
        }
        .frame(width: AppTheme.MetagDraft.stripCellWidth,
               height: AppTheme.MetagDraft.stripCellHeight)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xs, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xs, style: .continuous)
                .strokeBorder(
                    image == nil ? AppTheme.Border.subtleColor : AppTheme.Border.primaryColor,
                    lineWidth: AppTheme.BorderWidth.hairline
                )
        )
        // 到货那一下：从略小、半透明落到位。**每一格各自动一次**，
        // 因为它们是各自到的。
        .opacity(image == nil ? AppTheme.Opacity.strong : AppTheme.Opacity.opaque)
        .scaleEffect(image == nil ? 0.96 : 1)
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: image == nil)
    }
}
