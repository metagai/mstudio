import Foundation

/// 打开一部成片时，哪几镜要连旁白一起拿回来。
///
/// ## 为什么会有这个判断
///
/// `seedance / veo / veo-pro / grok` 是**原生出声**的：台词、音效、环境声都在成片的
/// 音轨里，而且同步是在模型内部完成的 —— 口型、脚步、门响都对得上帧。
/// 我们再把一条 TTS 旁白摆到用户手边，他铺上去要么把模型的声音压过去、
/// 要么和它同时响，两种都更差；而后期旁白只能对齐到镜头起点，其余全靠运气。
///
/// 反过来，`local / cloud` 的镜头是**纯视频流**。草案里有声音（旁白烧进了动态分镜），
/// 用户听着旁白点头付的钱，拿到手却是一条哑片 —— 那不是缺一个功能，是承诺破裂。
///
/// ## 判据只有一个出处
///
/// 引擎带不带原生音轨，取自 `/api/v1/pricing` 的 `native_audio`，
/// **不在客户端硬编一张引擎名单**。加一档模型时那张表必然忘记更新，
/// 而忘记的后果是静默的：新档位的原生声音被我们的 TTS 盖掉，没有任何一处报错。
/// Web 端同一套判据（`studio/.../services/metag/narration.ts`）。
enum MetagNarrationPlan {

    /// `/api/v1/pricing` 里自带音轨的档位 id。
    /// 报价单取不到就是空集 —— 一镜都不跳，宁可多给一条旁白也不让片子变哑。
    static func nativeAudioEngineIds(_ pricing: MetagGateway.Pricing?) -> Set<String> {
        Set((pricing?.engines ?? []).filter(\.native_audio).map(\.id))
    }

    /// 要连旁白一起拿回来的镜号。
    ///
    /// - `shotEngines` 为空（老网关、或还没确认出片）时一镜不跳：宁可多给一条音轨，
    ///   也不能让本该有声的片子变哑 —— 两种错的代价不对称。
    /// - 混档的片子逐镜判。整片一刀切会让无声档的那几镜变哑。
    static func shotsNeedingNarration(
        shots: Int,
        shotEngines: [String?]?,
        nativeAudioEngineIds: Set<String>
    ) -> [Int] {
        guard shots > 0 else { return [] }
        guard let shotEngines, !shotEngines.isEmpty else { return Array(0..<shots) }
        return (0..<shots).filter { i in
            // 短于镜头数的数组不代表"其余都是原生的"，那是缺数据。缺数据按要旁白处理。
            guard i < shotEngines.count, let id = shotEngines[i] else { return true }
            return !nativeAudioEngineIds.contains(id)
        }
    }

    /// 这一单要打开的镜号。
    ///
    /// 整单失败时网关会回 `salvaged` —— 已经渲好、被 worker 归档的那几镜。
    /// 用户已经全额退款，但**片子里能用的那部分不该跟着一起扔**。
    /// 没有 `salvaged` 的失败单没有任何可开的东西，不要去下载一批必然 404 的文件。
    static func shotsToOpen(shots: Int, status: String?, salvaged: [Int]?) -> [Int] {
        guard shots > 0 else { return [] }
        guard status == "failed" else { return Array(0..<shots) }
        guard let salvaged else { return [] }
        // 去重并排序：镜号来自服务端，界面按顺序铺，不能指望它已经是干净的。
        return Set(salvaged).filter { (0..<shots).contains($0) }.sorted()
    }
}
