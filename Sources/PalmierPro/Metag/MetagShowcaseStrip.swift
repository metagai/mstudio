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
    /// 播放器、定时器、观察者三样都交给它 —— **清理由 ARC 保证，
    /// 不由 `onDisappear` 保证**（SwiftUI 不保证那个回调一定到）。
    @State private var preview = ShowcasePreview()

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
        .onDisappear { stop(); preview.endAll() }
    }

    private func poster(_ film: MetagShowcase) -> some View {
        Button { play(film) } label: {
            ZStack {
                AsyncImage(url: film.poster) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    // 海报还没到的时候画一块底色，**不画一个"加载中"的字** ——
                    // 这一排是拿来看的，一行小字比一块安静的底色更吵。
                    AppTheme.Background.surfaceColor
                }
                // **停上去它就活了。**
                //
                // 这一排原来要点一下才动。而这是他打开 METAG 看到的第一样东西 ——
                // 一个视频产品，第一屏应该在他还没决定要不要试之前就先动给他看。
                //
                // 海报留在底下：播放器接手时不闪一下黑。
                if let live = preview.players[film.id] {
                    VideoPlayer(player: live)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
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
            // **播放键只在它还没动的时候出现。**
            //
            // 上一版它一直居中挂着，而现在停上去片子自己就播了 ——
            // 一个"点我播放"的按钮压在正在播的画面上，是多余的装饰，
            // 而多余的装饰正是精致的反面。
            //
            // 它现在只说一件事：**这里有一条片子**。
            // 一旦片子动起来，它就退场，把画面整个让出来。
            .overlay {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: AppTheme.FontSize.display))
                    .foregroundStyle(.white)
                    .shadow(AppTheme.Shadow.md)
                    .opacity(preview.players[film.id] == nil ? AppTheme.Opacity.strong : 0)
                    .animation(.easeOut(duration: AppTheme.Anim.transition), value: preview.players[film.id] == nil)
            }
            // 停上去轻轻抬一下。**只抬一点点** —— 这一排的主角是画面，不是动效。
            .scaleEffect(hovered == film.id ? 1.02 : 1)
            .animation(.easeOut(duration: AppTheme.Anim.hover), value: hovered)
            .onHover { inside in
                hovered = inside ? film.id : nil
                if inside {
                    preview.begin(film, fullPlayerOpen: playing != nil) { hovered == film.id }
                } else {
                    preview.end(film.id)
                }
            }
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
