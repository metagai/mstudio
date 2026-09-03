import AVKit
import SwiftUI

/// 首屏那一排真片子。点一张，就地播。
///
/// **点一下就能看到一条片子，不用注册、不用等。**
/// 原来这个位置是三行写死的例句，点一下直接开拍 —— 那条路的 Aha
/// 隔着九十秒到两分钟，而且要花他的额度。这一排的 Aha 是当场的。
@MainActor
struct MetagShowcaseStrip: View {
    let films: [MetagShowcase]
    @State private var playing: MetagShowcase?
    @State private var player: AVPlayer?
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            Text(L10n.string("Made with METAG"))
                .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(AppTheme.Text.tertiaryColor)

            HStack(alignment: .top, spacing: AppTheme.Spacing.smMd) {
                ForEach(films) { film in
                    poster(film)
                }
                Spacer(minLength: 0)
            }

            if let playing {
                VideoPlayer(player: player)
                    .frame(height: AppTheme.Showcase.playerHeight)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                    .transition(.opacity)
                Text(verbatim: playing.line)
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { stop() }
    }

    private func poster(_ film: MetagShowcase) -> some View {
        Button { play(film) } label: {
            AsyncImage(url: film.poster) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                // 海报还没到的时候画一块底色，**不画一个"加载中"的字** ——
                // 这一排是拿来看的，一行小字比一块安静的底色更吵。
                AppTheme.Background.surfaceColor
            }
            .frame(
                width: AppTheme.Showcase.posterHeight * film.aspect,
                height: AppTheme.Showcase.posterHeight
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    .stroke(
                        playing?.id == film.id ? AppTheme.Accent.brand : AppTheme.Border.subtleColor,
                        lineWidth: AppTheme.BorderWidth.hairline
                    )
            }
            // **居中、够大。** 上一版是左下角一个小圆点 —— 一个"点我看片子"
            // 的邀请藏在角落里，等于没发出去。
            .overlay {
                Image(systemName: playing?.id == film.id ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: AppTheme.FontSize.display))
                    .foregroundStyle(.white)
                    .shadow(AppTheme.Shadow.md)
                    .opacity(hovered == film.id ? 1 : AppTheme.Opacity.strong)
                    .scaleEffect(hovered == film.id ? 1.08 : 1)
                    .animation(.easeOut(duration: AppTheme.Anim.hover), value: hovered)
            }
            .onHover { hovered = $0 ? film.id : nil }
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(film.line)
        .accessibilityLabel(film.line)
    }

    /// 同一张再点一次是停 —— 不然他没有办法把它关掉。
    private func play(_ film: MetagShowcase) {
        if playing?.id == film.id {
            stop()
            return
        }
        let next = AVPlayer(url: film.reel)
        player = next
        playing = film
        next.play()
    }

    private func stop() {
        player?.pause()
        player = nil
        playing = nil
    }
}
