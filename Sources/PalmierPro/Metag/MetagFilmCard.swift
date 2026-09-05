import AVKit
import SwiftUI

/// 他自己的一部片子，在墙上的那一张。
///
/// ## 之前是一行字
///
/// 「我的作品」列的是片子，而它长得像一份日志：一行提示词、一行
/// 「几镜 · 多少 credits · 多久以前」、右边一个状态词，前面一个 96pt 的小图。
///
/// 而**每一条成片都带 `shot_0.mp4`** —— 我们手里有画面，他看不到。
/// （`docs/lessons.md` 第三十九条：东西真的有，只是那条线没接上。）
///
/// ## 现在
///
/// 一张大海报。**鼠标停上去，它自己动起来** —— 播第一镜，静音，循环。
/// 他不用点开就知道这是哪一部。
@MainActor
struct MetagFilmCard: View {
    let film: MetagGateway.FilmRow
    let poster: NSImage?
    let onOpen: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void
    var busy: Bool = false
    /// **不用停上去就自己在动。**
    ///
    /// 一整面墙十二张卡同时下十二段视频是灾难，所以那里是悬停才播。
    /// 而首屏只有一张 —— 他上一条片子 —— 那一张要**零点击**就在动着。
    /// 创始人 2026-08-10 点过名：「最近的项目和 Template Lib 有待重新设计
    /// （交互不 Aha 是原罪）」，判据是「一个刚回来的创作者，
    /// **零点击就能看见自己上次做的东西**」。
    var autoplay: Bool = false

    @State private var hovered = false
    @State private var player: AVPlayer?
    @State private var loop: NSObjectProtocol?

    private var openable: Bool { film.retrievable && film.status != "failed" }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            art
            Text(film.prompt ?? L10n.string("Untitled"))
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.primaryColor)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: meta)
                .font(.system(size: AppTheme.FontSize.xs))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
        }
        .opacity(openable ? AppTheme.Opacity.opaque : AppTheme.Opacity.medium)
        .onHover { inside in
            hovered = inside
            inside ? startPreview() : stopPreview()
        }
        .onAppear { if autoplay { startPreview() } }
        // **走的时候一定要放掉**，自动播那一张也不例外 ——
        // `stopPreview` 对它是空操作（它不跟鼠标走），所以这里直接放。
        .onDisappear(perform: releasePlayer)
    }

    private var art: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player).allowsHitTesting(false)
            } else if let poster {
                Image(nsImage: poster).resizable().aspectRatio(contentMode: .fill)
            } else {
                // 取不到就留一个安静的空格，**不摆占位的假图** ——
                // 那会让人以为片子长那样。
                AppTheme.Background.baseColor
            }
        }
        .aspectRatio(AppTheme.FilmWall.posterAspect, contentMode: .fill)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .strokeBorder(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.hairline)
        }
        .overlay(alignment: .topTrailing) { badge }
        .overlay(alignment: .bottomTrailing) { actions }
        .contentShape(Rectangle())
        .onTapGesture { if openable && !busy { onOpen() } }
        .pointerStyle(openable ? .link : .default)
        .help(openable ? L10n.string("Open in the editor") : statusText)
    }

    /// 状态做成角标，不是右边单独一列字 —— 那一列在墙上没有位置，
    /// 而**「这一部还取不取得到」他必须一眼看见**。
    @ViewBuilder
    private var badge: some View {
        if Self.showsBadge(status: film.status, retrievable: film.retrievable) {
            Text(verbatim: statusText)
                .font(.system(size: AppTheme.FontSize.xxs, weight: AppTheme.FontWeight.medium))
                .padding(.horizontal, AppTheme.Spacing.xs)
                .padding(.vertical, AppTheme.Spacing.xs)
                .background(Capsule().fill(.ultraThinMaterial))
                .foregroundStyle(AppTheme.Status.warningColor)
                .padding(AppTheme.Spacing.xs)
        }
    }

    /// 分享和删除**平时不占位置**，鼠标停上去才出现。
    /// 一面墙上每张卡都挂两个按钮，看的就不是片子了。
    @ViewBuilder
    private var actions: some View {
        if hovered {
            HStack(spacing: AppTheme.Spacing.xs) {
                iconButton("square.and.arrow.up", L10n.string("Share"), action: onShare)
                iconButton("xmark", L10n.string("Delete"), action: onDelete)
            }
            .padding(AppTheme.Spacing.xs)
            .transition(.opacity)
        }
    }

    private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.medium))
                .frame(width: AppTheme.IconSize.md, height: AppTheme.IconSize.md)
                .background(Circle().fill(.ultraThinMaterial))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .help(label)
        .accessibilityLabel(label)
    }

    private var statusText: String { Self.statusText(status: film.status, retrievable: film.retrievable) }
    private var meta: String { Self.meta(film) }

    /// 如实说：这一单的产物还在不在。**含糊其辞比说不出口更伤信任。**
    static func statusText(status: String, retrievable: Bool) -> String {
        status == "failed" ? L10n.string("Failed")
            : (retrievable ? L10n.string("Open") : L10n.string("Expired"))
    }

    /// 角标只在**他需要知道**的时候出现：这一部打不开了。
    /// 能打开的那些不挂角标 —— 一面墙上每张都贴一个「正常」，等于什么都没说。
    nonisolated static func showsBadge(status: String, retrievable: Bool) -> Bool {
        status == "failed" || !retrievable
    }

    /// **失败又退过款的，不能只报一个扣费数字。**
    /// 「4 镜 · 640 credits」读起来就是"失败了还扣我钱"。
    static func meta(_ film: MetagGateway.FilmRow) -> String {
        let money = film.refunded == true
            ? L10n.string("\(film.shots.formatted()) shots · refunded")
            : L10n.string("\(film.shots.formatted()) shots · \(film.credits.formatted()) credits")
        return money + " · " + MetagMyFilmsView.when(film.created_at)
    }

    /// 鼠标停上去才取地址、才建播放器。**一屏十二张卡不该同时下十二段视频。**
    private func startPreview() {
        guard openable, player == nil, let name = film.poster else { return }
        Task { @MainActor in
            guard let url = try? await MetagGateway.fileURL(job: film.job_id, name: name),
                  hovered || autoplay else { return }
            let next = AVPlayer(url: url)
            next.isMuted = true          // 一面墙同时出声是灾难
            next.actionAtItemEnd = .none
            // **一遍就停下的"自动播"比不播更糟** —— 他抬头时它已经不动了，
            // 而屏幕上留着一帧静止画面，看起来就是一张海报。
            // 循环这一段和 `ShowcasePreview` 是同一个写法，两处别分家。
            loop = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: next.currentItem, queue: .main
            ) { _ in
                Task { @MainActor in next.seek(to: .zero); next.play() }
            }
            player = next
            next.play()
        }
    }

    private func stopPreview() {
        // 自动播的那一张不跟着鼠标走。
        guard !autoplay else { return }
        releasePlayer()
    }

    /// **播放器和它的观察者一起走。** 只 `pause()` 不摘观察者，
    /// 那个闭包会一直持有 player，卡片消失了它还活着。
    private func releasePlayer() {
        player?.pause()
        player = nil
        if let loop { NotificationCenter.default.removeObserver(loop) }
        loop = nil
    }
}
