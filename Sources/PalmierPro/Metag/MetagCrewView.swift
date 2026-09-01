import SwiftUI

/// 等待期间的班底。**通告单，不是进度条。**
///
/// 纸感界面里画卡通脸会掉价，所以用剧组通告单的语言：一排字母徽章、职位、
/// 以及交接那一句。区别不在装饰，在于**它说的是谁在干什么，而不是干到百分之几**。
///
/// 到场是仪式（可以快、可以好看，只演一次）；**谁亮起来一律由真实阶段说了算**，
/// 没有任何定时器参与。见 `MetagCrew` 顶上的说明。
struct MetagCrewView: View {
    /// 网关报的当前阶段。为 nil 时一个人都不亮。
    let stage: String?
    /// 交接句里那个真实数字（镜数）。拿不到就不说那句话 —— 宁可少说一句。
    let shotCount: Int?

    /// 到场动画只演一次。**它不表示进度**，所以和 stage 无关。
    @State private var arrived = false

    private var current: MetagCrew.Member? { MetagCrew.current(stage: stage) }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            callSheet
            headline
        }
        .onAppear {
            withAnimation(.easeOut(duration: AppTheme.Anim.transition)) { arrived = true }
        }
    }

    // MARK: - 通告单那一行

    private var callSheet: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            ForEach(Array(MetagCrew.members.enumerated()), id: \.element.id) { index, member in
                badge(member)
                    .opacity(arrived ? 1 : 0)
                    .scaleEffect(arrived ? 1 : 0.86)
                    // 鱼贯入场：每人晚一点点。这是仪式，不是进度。
                    .animation(
                        .easeOut(duration: AppTheme.Anim.transition)
                            .delay(Double(index) * 0.06),
                        value: arrived
                    )
                if index < MetagCrew.members.count - 1 {
                    handoffRule(after: member)
                }
            }
        }
    }

    private func badge(_ member: MetagCrew.Member) -> some View {
        let standing = MetagCrew.standing(of: member, stage: stage)
        return ZStack {
            Circle()
                .fill(standing == .done
                      ? member.tint.opacity(AppTheme.Opacity.subtle)
                      : Color.clear)
            Circle()
                .strokeBorder(
                    standing == .working ? member.tint : AppTheme.Border.subtleColor,
                    lineWidth: standing == .working ? AppTheme.BorderWidth.medium : AppTheme.BorderWidth.hairline
                )
            Text(verbatim: member.monogram)
                .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(standing == .waiting ? AppTheme.Text.mutedColor : AppTheme.Text.primaryColor)
        }
        .frame(width: AppTheme.IconSize.lg, height: AppTheme.IconSize.lg)
        // 正在干活的那位稍微抬起来一点。**只有一档**，不做呼吸动画 ——
        // 持续动的东西会把注意力从画面上拽走，而用户此刻该看的是首帧。
        .scaleEffect(standing == .working ? 1.08 : 1)
        .animation(.easeOut(duration: AppTheme.Anim.hover), value: standing)
        .help("\(member.name) · \(L10n.string(key: member.title))")
        .accessibilityLabel(Text(verbatim: "\(member.name), \(L10n.string(key: member.title))"))
    }

    /// 两个人之间那道线。交活了才连上 —— **协作是看得见的交接，不是并排站着。**
    private func handoffRule(after member: MetagCrew.Member) -> some View {
        let passed = MetagCrew.standing(of: member, stage: stage) == .done
        return Rectangle()
            .fill(passed ? member.tint.opacity(AppTheme.Opacity.muted) : AppTheme.Border.subtleColor)
            .frame(width: AppTheme.Spacing.sm, height: AppTheme.BorderWidth.hairline)
            .animation(.easeOut(duration: AppTheme.Anim.transition), value: passed)
    }

    // MARK: - 他此刻说的那句话

    private var headline: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
            if let member = current {
                HStack(spacing: AppTheme.Spacing.xxs) {
                    Text(verbatim: member.name)
                        .font(.system(size: AppTheme.FontSize.smMd, weight: AppTheme.FontWeight.semibold))
                    Text(verbatim: "·")
                        .foregroundStyle(AppTheme.Text.mutedColor)
                    Text(L10n.string(key: member.title))
                        .foregroundStyle(AppTheme.Text.secondaryColor)
                }
                .font(.system(size: AppTheme.FontSize.smMd))
                Text(line(for: member))
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
            } else {
                // 阶段还没上来。不猜、不给数字、也不亮任何人。
                Text(L10n.string("Putting a crew together for this one…"))
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.mutedColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: AppTheme.Anim.transition), value: current?.id)
    }

    /// 有真实数字就说交接那句，没有就说他正在做什么。
    /// **不拿占位符凑** —— 一句"Nova handed me %@ shots"比不说更糟。
    private func line(for member: MetagCrew.Member) -> String {
        guard let template = member.tookOver, let shotCount, shotCount > 0 else {
            return L10n.string(key: member.doing)
        }
        return L10n.string(key: template).replacingOccurrences(of: "%@", with: shotCount.formatted())
    }
}
