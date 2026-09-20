import AVKit
import SwiftUI

/// 草案那条片子。**"先看一眼"里的"看"。**
///
/// ## 它一直都在
///
/// `cpu_worker` 出草案时就生成 `preview.mp4`（还混了配乐），网关按字节区间
/// 下发（`/files/{job}/preview.mp4`），web 的幕布一直在播它。
/// **只有 Mac 从来没解过 `preview` 这个字段** —— 于是这一屏给的是
/// 一排静态首帧加一堆输入框：那不是"看一眼"，那是"看一眼它的证据"。
///
/// 首页对外的承诺是"写一句话，看一眼你的片子"。在这之前，Mac 兑现了
/// 前半句。
///
/// ## 自动播
///
/// 他为这条片子等了九十秒、按过"起草"、而且这是一张模态表 ——
/// **这一刻他要的就是它开始动。** 让他再找一颗播放键，是把 Aha 推远一步。
struct MetagDraftPlayer: View {
    let jobId: String
    let name: String
    /// 画面左上角那枚标：**这块画面是什么**。
    ///
    /// 默认是草案（静帧）。免费试渲那一镜播的是真的成片画质，
    /// 那时候还印"静帧"就是一句假话 —— **而那一镜存在的全部意义，
    /// 正是让他看见"不是静帧"长什么样。**
    var label: String = L10n.string("Draft · still frames")

    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                // 还在拿带票地址。**不放占位图** —— 幕布刚刚才填满，
                // 这里再闪一张假图只会打断那一下。
                AppTheme.Background.baseColor
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        // **说出这是什么。**
        //
        // 草案按设计就是静帧加缓慢推拉（`workers/animatic.py`），而它看起来
        // 像一条成片。2026-09-20 一个用户看完它说"每一帧是镜头 PPT"——
        // 他说得没错，错的是我们从没告诉他这是草案。同一段画面，
        // 知道它是草案的人看到的是"第一步"，不知道的人看到的是"这就是成品"。
        .overlay(alignment: .topLeading) {
            Text(verbatim: label)
                .font(.system(size: AppTheme.FontSize.xxs, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(AppTheme.Text.primaryColor)
                .padding(.horizontal, AppTheme.Spacing.smMd)
                .padding(.vertical, AppTheme.Spacing.xs)
                .background(
                    Capsule().fill(AppTheme.Background.prominentColor
                        .opacity(AppTheme.Opacity.strong))
                )
                .padding(AppTheme.Spacing.smMd)
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .strokeBorder(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.hairline)
        )
        // **id 要带上 name。** 只用 jobId 的话，同一条草案里从静帧换成
        // 试渲那一镜时这段 task 不会重跑 —— 播放器还在播旧的那条，
        // 而标已经改成"成片画质"了：**最坏的一种错，屏幕上两个东西互相矛盾**。
        .task(id: "\(jobId)/\(name)") {
            guard let url = try? await MetagGateway.fileURL(job: jobId, name: name) else { return }
            let created = AVPlayer(url: url)
            player = created
            created.play()
        }
        .onDisappear {
            // 表关了声音要跟着停。**一条在背景里继续说话的旁白，
            // 比没有声音吓人得多。**
            player?.pause()
            player = nil
        }
    }
}
