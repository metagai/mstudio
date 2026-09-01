import SwiftUI

/// 订阅那一行。**和 studio 用同一套话** —— 同一个人在两端读到的不该不一样。
///
/// 这一行存在的理由是：`subscribed` 是个布尔，而「他自己取消了」和
/// 「他的卡扣不动了」在那个布尔里长得**一模一样** —— 而这两件事要他做的事
/// 完全相反：
///
/// - 取消 → **什么都不用做**，别让他以为已经断了
/// - 扣款失败 → 要他换卡，**且必须说清现在还没断**（Stripe 还会重试两三周）
///
/// 没订过的人这一行整个不出现 —— 不给他一句"你没有订阅"。
struct SubscriptionLine: View {
    @Bindable private var account = AccountService.shared

    var body: some View {
        if let text {
            HStack(spacing: AppTheme.Spacing.sm) {
                Text(verbatim: text)
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)

                // **管理入口不许挂在这一行里面。**
                //
                // 合伙人在 web 上栽过：管理按钮写在这一行内部，而这一行为
                // nil 时整段不渲染 —— 于是守着它的那个布尔一次都没起过作用，
                // 变异把它改成恒真，四条判据全绿。留着一个不做事的门，
                // 下一个人会以为门在那儿。所以它在这里是并列的一颗，
                // 有它自己的出现条件。
                if canManage {
                    Button(L10n.string("Manage")) {
                        Task { await account.openBillingPortal() }
                    }
                    .buttonStyle(.capsule(.secondary))
                    .controlSize(.small)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// 付过费的人才给管理入口 —— 没付过的人网关回 404，
    /// **不给他一个点进去报错的链接。**
    private var canManage: Bool {
        switch account.subscription {
        case .none: false
        case .active, .canceling, .pastDue, .ended: true
        }
    }

    private var text: String? {
        switch account.subscription {
        case .none:
            nil
        case .active(let until):
            L10n.string("Renews \(Self.day(until))")
        case .canceling(let until):
            L10n.string("Cancelled — yours until \(Self.day(until))")
        case .pastDue:
            L10n.string("This month's payment didn't go through. Nothing's cut off yet.")
        case .ended:
            L10n.string("Your subscription has ended.")
        }
    }

    private var tint: Color {
        switch account.subscription {
        case .pastDue: AppTheme.Status.warningColor
        case .canceling, .ended: AppTheme.Text.secondaryColor
        default: AppTheme.Text.tertiaryColor
        }
    }

    /// 日期用**系统地区格式**，不写死 —— 中文用户看到 `Oct 3, 2026` 会先愣一下。
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.abbreviated).day())
    }
}
