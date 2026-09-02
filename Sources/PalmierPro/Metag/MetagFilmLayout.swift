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
    /// 一部片子铺上时间线的**全部决定**：每一镜落在哪、每段旁白落在哪、主音量补多少。
    ///
    /// ## 为什么要有这个类型
    ///
    /// 这些决定原来散在 `MetagJobOpener.open()` 里 —— 那是一段要网络、
    /// 要编辑器、要真下载的异步流程，**判据够不着**。于是那条路上只有
    /// 几条"源码里那行还在吗"的断言。
    ///
    /// 而产品技术负责人在 web 那侧撞见的形状是：
    /// **判据覆盖的是回退路，而每一部片子走的是另一条。**
    /// Mac 这侧更彻底 —— 那条路一条行为判据都没有，
    /// 而在我们两个修完之前，它是**每一部片子**唯一走的路。
    struct Plan: Equatable {
        /// 每一镜的起始帧，按画面顺序。
        var shotStarts: [Int]
        /// 每一镜的**长度**（秒），按画面顺序。
        ///
        /// **这个字段是这份铺法真正被用上的那一半。**
        /// 上一版只回起始帧，而调用点用的是 `addClips`，它按
        /// `clipDurationFrames` → `asset.duration` 定每段长度 ——
        /// 而那个值在铺片子那一刻还是 0，于是 N 个镜头全部一帧宽、挤在开头。
        /// **算出来的起始帧一次都没被消费过，而判据测的正是它。**
        var shotSeconds: [Double]
        /// 每一段旁白：落在哪一镜、哪一帧。
        var narrations: [Int: Int]
        /// 乘到每个出声片段上的倍数。
        var volume: Double
    }

    /// 把一份任务详情算成一份铺法。
    ///
    /// `measured` 是从**下载下来的文件**上量的秒数（不是 `MediaAsset.duration`
    /// —— 那个在铺片子那一刻还是 0）。`frame` 由时间线自己做换算，
    /// 这里没有 fps 可传错。
    static func plan(
        shotIndices: [Int],
        narrationIndices: Set<Int>,
        clipSeconds: [Double]?,
        masterGainDB: Double?,
        measured: (Int) -> Double,
        frame: (Double) -> Int
    ) -> Plan {
        // **`clipSeconds` 按槽位取，而 `shot_clips` 是按原始镜号排的。**
        // 抢救回来的片子（只有一部分镜可用）或者某几镜下载失败时，
        // 两者对不上 —— 每一段都会按错误那一镜的长度铺。
        let byShot = shotIndices.map { shot -> Double? in
            guard let clipSeconds, shot < clipSeconds.count, clipSeconds[shot] > 0 else { return nil }
            return clipSeconds[shot]
        }
        let lengths = lengths(shotCount: shotIndices.count, authoritative: byShot, measured: measured)
        let starts = runningStarts(lengths).map(frame)
        let placements = narrationFrames(
            shots: shotIndices, narrations: narrationIndices, starts: starts
        )
        return Plan(
            shotStarts: starts,
            shotSeconds: lengths,
            narrations: Dictionary(uniqueKeysWithValues: placements.map { ($0.shot, $0.frame) }),
            volume: volumeFactor(masterGainDB: masterGainDB)
        )
    }

    /// 主音量差 → 线性倍数。
    ///
    /// 时间线上没有"主音量"这一层，只有每个片段自己的 `volume`。
    /// **同一个倍数乘到每一个出声的片段上**，配比不变 —— 那正是主音量的定义。
    ///
    /// 字段缺席时返回 1（不动），而**不动就是偏 6 dB** ——
    /// 这不是中性的默认，只是我们能做的最诚实的一件事：不瞎补。
    ///
    /// 上下各夹一档：网关给出一个荒谬的数时，宁可少补，也不要把他的片子削顶。
    static func volumeFactor(masterGainDB: Double?) -> Double {
        guard let db = masterGainDB, db.isFinite else { return 1 }
        return pow(10, min(24, max(-24, db)) / 20)
    }

    /// 把主音量乘到每一个片段上。
    ///
    /// 抽出来是为了让判据能直接跑它 —— 留在调用点的话，
    /// 唯一的问法就是"源码里那个循环还在吗"。
    static func applyMasterGain(_ factor: Double, to tracks: inout [Track]) {
        guard factor != 1, factor > 0 else { return }
        for t in tracks.indices {
            for c in tracks[t].clips.indices {
                tracks[t].clips[c].volume *= factor
            }
        }
    }

    /// 每一段旁白落在哪一帧。
    ///
    /// **抽出来是因为上一版判据在比源码字符串**：它断言那行
    /// `startFrame: starts[slot]` 还在。而把 `fps` 传成 0 —— 两个字符串
    /// 一字不改 —— 每一段旁白都落到了开头（正是 web 端那次「多个音轨叠加」），
    /// 判据全绿。
    ///
    /// 现在它是个纯函数，判据直接问它：**哪一段旁白落在哪一帧**。
    ///
    /// `shots` 是画面按顺序的镜号，`narrations` 是有旁白的那几镜的镜号。
    /// 原生出声的镜没有旁白，所以两者不是一一对应 —— 按镜号配，不按位置配。
    static func narrationFrames(
        shots: [Int], narrations: Set<Int>, starts: [Int]
    ) -> [(shot: Int, frame: Int)] {
        shots.enumerated().compactMap { slot, shot in
            guard narrations.contains(shot), slot < starts.count else { return nil }
            return (shot, starts[slot])
        }
    }

    /// 每一镜的起点，**单位是秒**。
    ///
    /// 原来这里收一个 `fps` 自己换成帧。把它传成 0 —— 源码字符串一字不改 ——
    /// 每一镜只推进 1 帧，十一镜全叠在前十一帧上，
    /// 而它长得跟"铺好了"一模一样。**判据看不见这种错，所以让它传不了。**
    /// 换算交给 `EditorViewModel.frame(atSeconds:)`，fps 从时间线自己读。
    /// 全都量不到的时候，一镜按多长算。
    ///
    /// 走到这里意味着**每个文件都读不出时长** —— 那时摆多长都是猜。
    /// 选一个不会让它们叠在一起的数：叠在一起看起来像"什么都没发生"，
    /// 而长度猜偏一点，他一眼就看得出来、也拖得动。
    static let nominalShotSeconds: Double = 4

    /// 每一镜的长度（秒）。权威值优先，量不到的拿量得到的中位数顶上。
    static func lengths(
        shotCount: Int, authoritative: [Double?], measured: (Int) -> Double
    ) -> [Double] {
        var out: [Double] = (0..<shotCount).map { i in
            if i < authoritative.count, let s = authoritative[i], s > 0 { return s }
            let m = measured(i)
            return m.isFinite && m > 0 ? m : 0
        }
        // 量不到的那几镜，拿量得到的那些的中位数顶上 ——
        // 同一部片子里各镜长度接近，中位数是这里能拿到的最好的猜。
        // 中位数不是最小值：**一镜坏掉不该把整片压扁。**
        let known = out.filter { $0 > 0 }.sorted()
        let fill = known.isEmpty ? nominalShotSeconds : known[known.count / 2]
        return out.map { $0 > 0 ? $0 : fill }
    }

    /// 长度算完直接给起点。判据里最常问的就是这个组合。
    static func lengthsAndStarts(
        shotCount: Int, authoritative: [Double?], measured: (Int) -> Double
    ) -> [Double] {
        runningStarts(lengths(shotCount: shotCount, authoritative: authoritative, measured: measured))
    }

    /// 逐段累加成起点。
    static func runningStarts(_ lengths: [Double]) -> [Double] {
        var starts: [Double] = []
        var cursor = 0.0
        for length in lengths {
            starts.append(cursor)
            cursor += length
        }
        return starts
    }
}
