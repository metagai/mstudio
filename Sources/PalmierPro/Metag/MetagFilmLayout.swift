import Foundation

/// 把一条 METAG 片子**铺到时间线上**。
///
/// ## 之前发生的事
///
/// 用户写一句话、等九十秒、按下出片、付了 credits ——
/// 拿到的是**素材库里 N 个散文件和一条空时间线**。他得自己把每一镜拖进去、
/// 排好序、再把旁白一条条对齐到各自那一镜。
///
/// `addMediaAsset` 只把素材加进库，从来不铺时间线；而 `MetagJobOpener`
/// 只调它。这个产品的承诺是"一句话变成一条片子"，交付的是**一堆配料**。
///
/// 网关那侧早就为此准备好了 `shot_clips`，注释写得很清楚：
/// 「一条压平的片子在时间线上只有一个色块，拆不开、换不了序、改不了字幕。
/// 有了这份清单，编辑器铺的是 N 段可编辑素材。」
///
/// ## 三条轨，一步撤销
///
/// 画面按镜号顺次铺；配乐从头铺一条；**旁白对齐到各自那一镜的起点** ——
/// 旁白比镜头短，一段接一段挨着放会越走越偏，第四镜的话会压在第三镜上。
///
/// 整件事是一步撤销：他做的是"打开一条片子"这一个动作，
/// 不是"添加了十一次素材"。
enum MetagFilmLayout {
    /// 每一镜的起始帧。
    ///
    /// 优先用网关给的逐段时长（`shot_clips[i].seconds`）—— 那是权威的。
    /// 拿不到就退回按素材实测时长累加：**宁可自己量，也不要凭空假设等长**。
    static func startFrames(
        shotCount: Int,
        clipSeconds: [Double]?,
        fps: Int,
        measured: (Int) -> Int
    ) -> [Int] {
        var frames: [Int] = []
        var cursor = 0
        for i in 0..<shotCount {
            frames.append(cursor)
            if let seconds = clipSeconds, i < seconds.count, seconds[i] > 0 {
                cursor += max(1, Int((seconds[i] * Double(fps)).rounded()))
            } else {
                cursor += max(1, measured(i))
            }
        }
        return frames
    }
}
