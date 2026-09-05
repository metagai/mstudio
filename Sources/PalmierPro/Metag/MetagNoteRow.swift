import SwiftUI

/// 出事的那一句话，以及它旁边该不该有一扇门。
///
/// **抽出来是为了让判据能直接渲它。** 上一版这一行长在
/// `MetagDraftSheet` 的 body 里，而那个 body 要一整套状态才起得来 ——
/// 于是"门有没有真的画出来"这个问题只能靠读源码回答，
/// 而**读源码回答的问题，判据不算数**。
@MainActor
struct MetagNoteRow: View {
    let note: String
    let door: MetagDraftModel.NoteDoor?

    var body: some View {
        HStack(spacing: AppTheme.Spacing.smMd) {
            Text(note)
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Status.warningColor)
            if door == .topUp {
                // **门就在这句话旁边。** `buyCreditPack` 已经包了全部：
                // 拉价目、开收银台、埋点、切回来之后轮询到账。
                //
                // 30 天真数：撞上额度墙 4 人 → 打开收银台 1 人，丢掉 75%。
                // 这是有真人走过的步骤里转化最差的一格，而它此前给的是
                // 一句指路（「在设置 › 账户里加油或订阅」）——
                // 要他记住一条路径、退出这一屏、自己找过去，
                // 而他手里正有一条刚看完的草案。
                Button(L10n.string("Buy credits")) {
                    AccountService.shared.buyCreditPack()
                }
                .buttonStyle(.capsule(.prominent, size: .small))
                .disabled(AccountService.shared.isBuyingCredits)
            }
        }
    }
}
