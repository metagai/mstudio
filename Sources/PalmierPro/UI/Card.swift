import SwiftUI

// MARK: - 一块卡片，全 app 只有这一种画法
//
// ## 这块砖一直都在，只是没人找得到
//
// 2026-09-01 我数出「`RoundedRectangle(cornerRadius:` 出现 133 次 / 57 个文件」，
// 就断定"全 app 没有卡片这个东西"，然后动手新造了一块。**造完才发现它早就有** ——
// `themedSurface(_:cornerRadius:)`，fill + 同圆角描边，一模一样的东西，
// 藏在一个叫 `HoverHighlight.swift` 的文件里，全仓只有 11 处在用。
//
// **一块找不到的砖不算砖。** 57 个文件手搓卡片，不是因为大家不想复用，
// 是因为想复用的人搜 "Card" 搜不到任何东西。而我差一点就把它变成第二块砖 ——
// 那样问题不是被解决，是被翻倍。
//
// 所以这个文件做两件事：把那块砖搬到它名字该在的地方，然后只留一块。
//
// ## 那 133 个数字也是错的
//
// 我数的是 `RoundedRectangle(cornerRadius` 的出现次数，然后管它叫"手搓卡片"。
// 逐个分类之后：37 处是 `clipShape`（裁图，本来就不是卡片）、39 处是选中环/焦点圈、
// 26 处是悬停填充和代码块底色，**真正 fill+描边的容器只有 3 处**。
//
// 数一个东西然后管它叫另一个名字 —— 这和"判据看了 0 个 key 还报绿"是同一族。

extension View {
    /// 一块卡片的**表面**：同一个圆角的填充 + 描边。
    ///
    /// 需要内边距和阴影的场合用 `Card`；只要这层皮就用它
    /// （行、磁贴、分组，它们各自的内边距不一样）。
    func cardSurface(
        _ fill: Color = AppTheme.Background.prominentColor,
        cornerRadius: CGFloat = AppTheme.Radius.mdLg,
        border: Color = AppTheme.Border.subtleColor,
        borderWidth: CGFloat = AppTheme.BorderWidth.thin
    ) -> some View {
        background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(fill))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(border, lineWidth: borderWidth)
            )
    }
}

/// 常见的那一种：一块有内边距的卡片。
///
/// 乐高像乐高不是因为积木好看，是因为**每一块的接口都一样**。
/// 这就是那个接口 —— 它只包 `cardSurface`，所以改一次圆角，全 app 一起变。
struct Card<Content: View>: View {
    enum Elevation {
        /// 贴在面板上，不浮起。列表里的行、设置里的分组。
        case flat
        /// 浮起来，带阴影。弹层、草案卡、需要"拿在手上"的东西。
        case raised
    }

    var elevation: Elevation = .flat
    var padding: CGFloat = AppTheme.Spacing.mdLg
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .cardSurface(elevation == .raised
                         ? AppTheme.Background.raisedColor
                         : AppTheme.Background.prominentColor)
            .modifier(CardShadow(on: elevation == .raised))
    }
}

/// 阴影只有浮起的那一档有。**平的那一档不加阴影** ——
/// 面板上每块都投影，等于没有一块是浮起来的。
private struct CardShadow: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on { content.shadow(AppTheme.Shadow.md) } else { content }
    }
}
