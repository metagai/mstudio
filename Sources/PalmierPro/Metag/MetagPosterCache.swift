import AVFoundation
import AppKit

/// 「我的作品」那一屏的缩略图。
///
/// ## 为什么是从视频里取一帧
///
/// 那一屏叫「我的作品」、列的是片子，而在这之前**整屏是文字** —— 首页的
/// 项目卡有缩略图，这一屏没有。这是它最大的高级感缺口。
///
/// 我原本想要网关加一个 `first_frame`。产品技术负责人否掉了，理由比我的提议好：
/// **首帧只活在 Redis 的任务哈希里，过了 TTL 就没有** —— 缩略图会随着时间
/// 一张张消失，那比一张都没有更糟。他改成回 `poster: "shot_0.mp4"`，
/// 每一条成片都有，而且它就是第一镜本身。
///
/// ## 不整片下载
///
/// `AVAssetImageGenerator` 对着远端 URL 只取它需要的那几个字节 ——
/// 一屏十行不会变成十次整片下载。容差留默认：要求精确到帧会逼它多下数据，
/// 而这是一张 96 点宽的缩略图，差一帧看不出来。
@MainActor
@Observable
final class MetagPosterCache {
    static let shared = MetagPosterCache()

    private var images: [String: NSImage] = [:]
    @ObservationIgnored private var inFlight: Set<String> = []

    private init() {}

    func poster(for jobId: String) -> NSImage? { images[jobId] }

    /// 取一次就够。**同一行重绘多次不该重下多次** —— 列表滚动时
    /// SwiftUI 会反复调用 body。
    func load(jobId: String, name: String) {
        guard images[jobId] == nil, !inFlight.contains(jobId) else { return }
        inFlight.insert(jobId)
        Task {
            let image = await Self.firstFrame(jobId: jobId, name: name)
            inFlight.remove(jobId)
            guard let image else { return }
            images[jobId] = image
        }
    }

    /// 取不到就当没有 —— **不摆一个占位的假图**，那会让人以为片子长那样。
    private nonisolated static func firstFrame(jobId: String, name: String) async -> NSImage? {
        guard let url = try? await MetagGateway.fileURL(job: jobId, name: name) else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        guard let cg = try? await generator.image(at: .zero).image else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }
}
