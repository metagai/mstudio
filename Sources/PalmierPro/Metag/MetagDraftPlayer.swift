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
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .strokeBorder(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.hairline)
        )
        .task(id: jobId) {
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
