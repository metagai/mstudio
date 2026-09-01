import SwiftUI

/// 一块**卡片**。全 app 只有这一种画法。
///
/// ## 为什么需要它
///
/// 2026-09-01 数了一遍：`RoundedRectangle(cornerRadius:` 在 57 个文件里出现
/// **133 次** —— 每一屏都在手搓自己的卡片，圆角、描边、底色、阴影各挑各的。
/// 单独看每一处都合理，合起来就是"这些屏不像同一个产品"。
///
/// **这就是"乐高感"的反面。** 乐高之所以像乐高，不是因为积木好看，
/// 是因为**每一块的接口都一样**：随便两块都能拼，拼出来还是一套东西。
/// 一个到处手搓卡片的界面，是 133 种互不兼容的积木。
///
/// 所以先立这一块砖，再把手搓的一处处换过来 —— 换完之后，
/// 改一次圆角，全 app 一起变。
struct Card<Content: View>: View {
    enum Elevation {
        /// 贴在面板上的一块，不浮起。用于列表里的行、设置里的分组。
        case flat
        /// 浮起来的一块，带阴影。用于弹层、草案卡、需要"拿在手上"的东西。
        case raised
    }

    var elevation: Elevation = .flat
    /// 内边距。默认那一档适合大多数场合；密集列表里可以收紧。
    var padding: CGFloat = AppTheme.Spacing.mdLg
    @ViewBuilder var content: () -> Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppTheme.Radius.mdLg, style: .continuous)
    }

    var body: some View {
        content()
            .padding(padding)
            .background(
                shape.fill(elevation == .raised
                           ? AppTheme.Background.raisedColor
                           : AppTheme.Background.prominentColor)
            )
            .overlay(shape.strokeBorder(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.hairline))
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

extension View {
    /// 把这一段包成一块卡片。
    func card(_ elevation: Card<Self>.Elevation = .flat,
              padding: CGFloat = AppTheme.Spacing.mdLg) -> some View {
        Card(elevation: elevation, padding: padding) { self }
    }
}
