import Foundation

/// 「第 2 镜用了你的第 1 张图（当首帧）」。
///
/// ## 为什么这一句值得单独一个类型
///
/// A0 决定二点名了我们真正稀有的那件事：**一句话 → 分镜 → 把用户自己的图
/// 分派到具体镜上**（2026-09-05 实测跑通：镜0→素材0、镜1→素材1、镜2→素材2）。
///
/// **而客户端从头到尾看不见它发生过。** 他传三张图进去，导演逐镜分派了，
/// 屏幕上没有一个字说这件事 —— 他只会以为"图大概被参考了吧"。
/// 我们最稀有的能力，用户不知道它存在。
///
/// ## 两条规矩
///
/// **一、没有数据就一个字都不说。** `asset` 为 nil 就是"这一镜没用他的图"，
/// 那时不许出现任何占位文案 —— 同"不猜镜数"那条：印一个猜出来的东西，
/// 比不印更糟。而这两个键网关**现在还没回**（2026-09-07 核过两条 job 路都没有），
/// 所以今天全仓运行起来它一句话都不会说，**这是对的**：
/// 接线的那一半在网关那侧，而界面这一半不该等到那天才开始存在。
///
/// **二、`reference` 和 `first_frame` 对用户的意思完全不同。**
/// 一个是"照着这个感觉画"，一个是"这一镜就从这张图开始"。
/// 混成一句"用了你的图"，等于把我们唯一的差异化讲成了一句废话。
enum MetagAssetUse: String, CaseIterable, Sendable {
    /// 照着这个感觉画。
    case reference
    /// 这一镜就从这张图开始。
    case firstFrame = "first_frame"

    /// 认不出来的一律 nil —— **不猜**。网关那侧 `storyboard.py:749`
    /// 只允许这两个取值并且会校验，所以第三种值只可能是契约变了，
    /// 那时候闭嘴比编一句强。
    init?(_ raw: String?) {
        guard let raw, let value = MetagAssetUse(rawValue: raw) else { return nil }
        self = value
    }

    /// 一句人话。`shot` 和 `asset` 都是**从 1 开始数给人看的**，
    /// 不是数组下标 —— 屏幕上说「第 0 镜」没有人看得懂。
    @MainActor func sentence(shot: Int, asset: Int) -> String {
        switch self {
        case .reference:
            L10n.string("Shot \(shot.formatted()) takes its look from your image \(asset.formatted())")
        case .firstFrame:
            L10n.string("Shot \(shot.formatted()) opens on your image \(asset.formatted())")
        }
    }

    /// 一整份分镜里，逐镜那几句话。**没有一镜用到他的图就返回空** ——
    /// 调用方据此决定这一块整个不出现。
    @MainActor static func sentences(for shots: [MetagGateway.Job.Shot]) -> [String] {
        shots.enumerated().compactMap { index, shot in
            guard let asset = shot.asset, let use = MetagAssetUse(shot.asset_use) else { return nil }
            return use.sentence(shot: index + 1, asset: asset + 1)
        }
    }
}
