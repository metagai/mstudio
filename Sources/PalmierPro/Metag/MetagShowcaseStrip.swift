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
    @State private var previews: [String: AVPlayer] = [:]
    @State private var previewTasks: [String: Task<Void, Never>] = [:]
    @State private var loopObservers: [String: NSObjectProtocol] = [:]

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
        .onDisappear { stop(); endAllPreviews() }
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
                if let preview = previews[film.id] {
                    VideoPlayer(player: preview)
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
                    .opacity(previews[film.id] == nil ? AppTheme.Opacity.strong : 0)
                    .animation(.easeOut(duration: AppTheme.Anim.transition), value: previews[film.id] == nil)
            }
            // 停上去轻轻抬一下。**只抬一点点** —— 这一排的主角是画面，不是动效。
            .scaleEffect(hovered == film.id ? 1.02 : 1)
            .animation(.easeOut(duration: AppTheme.Anim.hover), value: hovered)
            .onHover { inside in
                hovered = inside ? film.id : nil
                inside ? beginPreview(film) : endPreview(film)
            }
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(film.line)
        .accessibilityLabel(film.line)
    }

    /// 停上去 → 就地无声试播；移开 → 停。
    ///
    /// **等一下再开。** 鼠标横扫过这一排时不该同时起三个播放器 ——
    /// 那既费机器，看起来也慌。180ms 是"停下来看"和"路过"的分界。
    /// 该不该为这一张起一个试播。**抽出来是因为判据没有鼠标** ——
    /// 留在闭包里的话，唯一的问法就是"源码里那行还在吗"。
    nonisolated static func shouldPreview(
        alreadyPlaying: Bool, alreadyPreviewing: Bool
    ) -> Bool {
        // 大播放器开着的时候不抢它；同一张已经在试播就别再起一个。
        !alreadyPlaying && !alreadyPreviewing
    }

    private func beginPreview(_ film: MetagShowcase) {
        guard Self.shouldPreview(alreadyPlaying: playing != nil,
                                 alreadyPreviewing: previews[film.id] != nil) else { return }
        previewTasks[film.id]?.cancel()
        previewTasks[film.id] = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, hovered == film.id, playing == nil else { return }
            let player = AVPlayer(url: film.reel)
            player.isMuted = true            // 一排同时出声是灾难
            player.actionAtItemEnd = .none
            // 循环：他停在那儿看第二遍是常事，而一条停住的片子看起来像卡住了。
            loopObservers[film.id] = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem, queue: .main
            ) { _ in
                Task { @MainActor in player.seek(to: .zero); player.play() }
            }
            previews[film.id] = player
            player.play()
        }
    }

    private func endPreview(_ film: MetagShowcase) {
        previewTasks[film.id]?.cancel()
        previewTasks[film.id] = nil
        previews[film.id]?.pause()
        previews[film.id] = nil
        if let token = loopObservers.removeValue(forKey: film.id) {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func endAllPreviews() {
        for id in previews.keys { previews[id]?.pause() }
        previews.removeAll()
        previewTasks.values.forEach { $0.cancel() }
        previewTasks.removeAll()
        loopObservers.values.forEach(NotificationCenter.default.removeObserver)
        loopObservers.removeAll()
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
