import AVFoundation
import CoreGraphics

/// 从视频里取一帧当缩略图。
///
/// ImageEncoder.thumbnail 走 ImageIO，只认静图。这一份原本藏在
/// MediaTab+Search 的一个 private View 里，做"多版本择优"时需要同一件事 ——
/// 与其抄一份，不如挪出来。
enum VideoThumbnail {
    /// 容差 1 秒：精确寻帧要解到关键帧之后，对一张缩略图不值得。
    static func image(url: URL, at seconds: Double, maxSize: CGFloat = 240) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        guard (try? await asset.loadTracks(withMediaType: .video).first) != nil else { return nil }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSize, height: maxSize)
        let tolerance = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        return try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }
}
