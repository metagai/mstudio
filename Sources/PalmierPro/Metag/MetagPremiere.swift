import SwiftUI

/// **首映。** 他的片子落地的那一刻，屏幕上放的是片子，不是一个工程。
///
/// ## 之前那一刻是什么样
///
/// 他写了一句话、等了两分钟、付了 credits —— 然后画面里出现的是
/// 十一个片段、三条轨、一个检查器面板，和**侧边栏里一句「已载入 5 镜」**。
///
/// 那句话是机器在报工，不是产品在交付。**而他不是剪辑师。**
/// 这个产品答应他的是"一句话变成一条片子"，兑现的方式却是把一份工程推给他，
/// 让他自己去找播放键。
///
/// > 魔法在这一秒停下，机器从这一秒开始。
///
/// ## 现在
///
/// 落地即播，从头播。预览上浮起一层很轻的幕，只说一句「你的片子」，
/// 下面三个选择：**留下它 · 再来一遍 · 我自己改**。
/// 播完自己退去，Esc 也退。
///
/// ## 为什么不另起一个播放器
///
/// 想过：把刚下载的那几镜用 `AVQueuePlayer` 连起来播，简单得多。
/// **但那样没有配乐** —— 配乐是时间线上单独一条轨（`music_bed`）。
/// 于是首映放的和他拿到的不是同一条片子，而这个仓库为这句话栽过：
/// 「他看的那条片子，和他拿到的那条不是同一条。」
///
/// 所以首映播的就是**时间线本身**。慢一点、麻烦一点，但它是真的。
struct MetagPremiere: Equatable, Sendable {
    let jobId: String
    let shots: Int
    /// 这一版是不是从失败里抢救回来的 —— 那时不该说"你的片子"说得那么满。
    let salvaged: Bool

    /// 请不请他把这条发出去。
    ///
    /// **抢救回来的那一版不请** —— 那时我们自己都不说"你的片子"说得那么满
    /// （见 `headline`），却请他发出去，等于拿他的社交信誉赌我们的残次品。
    ///
    /// 这是个属性而不是视图里的一个 `if`：判据要能直接问这件事，
    /// 而不是去数像素或者读源码字符串。
    var offersShare: Bool { !salvaged }

    @MainActor
    static func headline(shots: Int, salvaged: Bool) -> String {
        salvaged
            ? L10n.string("Here's what we could save — \(shots.formatted()) shots")
            : L10n.string("Your film · \(shots.formatted()) shots")
    }
}

/// 浮在预览上的那层幕。**很轻** —— 它盖住的是他刚拿到的东西。
@MainActor
struct MetagPremiereBar: View {
    let premiere: MetagPremiere
    let onKeep: () -> Void
    let onAgain: () -> Void
    /// 把公开链接放进剪贴板。**抢救回来的那一版不给这个** —— 见下面。
    let onShare: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.Spacing.smMd) {
            Text(verbatim: MetagPremiere.headline(shots: premiere.shots, salvaged: premiere.salvaged))
                .font(.system(size: AppTheme.FontSize.mdLg, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(AppTheme.Text.primaryColor)

            HStack(spacing: AppTheme.Spacing.smMd) {
                // **留下它排第一。** 「愿不愿意把它留下来」就是我们量的那个
                // 内容质量指标，而在此之前它只在菜单栏第二层里。
                Button(L10n.string("Keep it")) { onKeep() }
                    .buttonStyle(.capsule(.prominent, size: .regular))
                Button(L10n.string("Again")) { onAgain() }
                    .buttonStyle(.capsule(.secondary, size: .regular))
                // **"我自己改"不是主按钮。** 他要是想剪，点一下就走；
                // 而把剪辑摆在最前，等于又把工程推给了他。
                Button(L10n.string("I'll edit it")) { onDismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                // **他刚看完自己的片子，下一个动作多半是给人看。**
                //
                // 上一版这里写着「不新增按钮 —— 首映条仍是三颗」，那句话是对的，
                // 但它防的是**把控制面板推给他**（当时"留下它"通向六个下拉框）。
                // 分享不是面板：一次点击，链接进剪贴板。
                // 而在此之前，分享**只存在于「我的片子」列表里**
                // （全仓 `.shared` 埋点只有那一个调用点）—— 也就是说，
                // 他最想分享的那一刻，屏幕上没有这个动作。
                //
                // 所以它加进来了，但**不是胶囊**：主次仍然是"留下它"。
                //
                // ⚠ **抢救回来的那一版不给分享。** 那时我们自己都不说"你的片子"
                // 说得那么满（见 `headline`），却请他把它发出去 —— 那是拿他的
                // 社交信誉去赌我们的残次品。
                if premiere.offersShare {
                    Button(L10n.string("Share")) { onShare() }
                        .buttonStyle(.plain)
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.secondaryColor)
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.mdLg)
        // 幕用**磨砂**而不是实心：它盖在他刚拿到的片子上面，
        // 下面那点画面透出来，这一层才像"浮着"，不像"挡着"。
        .cardSurface(
            .clear,
            cornerRadius: AppTheme.Radius.lg,
            borderWidth: AppTheme.BorderWidth.hairline
        )
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .shadow(AppTheme.Shadow.lg)
        .padding(.bottom, AppTheme.Spacing.xl)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        // Esc 退幕。**他随时能把它推开** —— 一层推不开的幕，
        // 第二次看到就是打扰。
        .onExitCommand(perform: onDismiss)
    }
}
