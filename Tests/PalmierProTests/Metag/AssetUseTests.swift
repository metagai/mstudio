import Foundation
import Testing
@testable import PalmierPro

/// **我们最稀有的能力，用户看不见它存在。**
///
/// A0 决定二点名的那件事是「一句话 → 分镜 → 把用户自己的图分派到具体镜上」
/// （2026-09-05 实测跑通）。而 09-07 逐环核过：分镜里有 `asset`/`asset_use`、
/// worker 真的按它拼 references，**而两条 job 路都没把这两个键回给客户端**。
///
/// 他传三张图进去、导演逐镜分派了，屏幕上没有一个字说这件事。
@Suite("他的图用在哪一镜")
@MainActor
struct AssetUseTests {
    private static func shot(asset: Int?, use: String?) -> MetagGateway.Job.Shot {
        let json = """
        {"asset":\(asset.map(String.init) ?? "null"),
         "asset_use":\(use.map { "\"\($0)\"" } ?? "null"),
         "narration":"","video":"v.mp4","audio":""}
        """
        return try! JSONDecoder().decode(MetagGateway.Job.Shot.self, from: Data(json.utf8))
    }

    /// **没有数据就一个字都不说。** 网关那一半还没接，那时不许有占位文案。
    @Test(arguments: [(nil, nil), (nil, "reference"), (0, nil)] as [(Int?, String?)])
    func nothingIsSaidWithoutBothKeys(asset: Int?, use: String?) {
        #expect(MetagAssetUse.sentences(for: [Self.shot(asset: asset, use: use)]).isEmpty)
    }

    /// 认不出的取值一律闭嘴 —— `storyboard.py` 只允许两种并且会校验，
    /// 出现第三种只可能是契约变了，那时候编一句比不说更糟。
    @Test(arguments: ["", "background", "REFERENCE", "first frame"])
    func unknownUsesStaySilent(use: String) {
        #expect(MetagAssetUse(use) == nil)
        #expect(MetagAssetUse.sentences(for: [Self.shot(asset: 0, use: use)]).isEmpty)
    }

    /// **两种用法说的话必须不一样。**
    /// 一个是"照着这个感觉画"，一个是"这一镜就从这张图开始" ——
    /// 混成一句"用了你的图"，等于把唯一的差异化讲成一句废话。
    @Test func theTwoUsesReadDifferently() {
        let ref = MetagAssetUse.reference.sentence(shot: 2, asset: 1)
        let first = MetagAssetUse.firstFrame.sentence(shot: 2, asset: 1)
        #expect(ref != first)
    }

    /// **镜号和图号都从 1 开始数给人看。** 屏幕上说「第 0 镜」没有人看得懂。
    @Test func humansCountFromOne() {
        let lines = MetagAssetUse.sentences(for: [
            Self.shot(asset: 0, use: "first_frame"),
            Self.shot(asset: 1, use: "reference"),
        ])
        #expect(lines.count == 2)
        #expect(lines[0].contains("1"), "第一镜第一张图应该都印成 1：\(lines[0])")
        #expect(!lines[0].contains("0"), "把数组下标印给用户了：\(lines[0])")
    }

    /// 只说用到他图的那几镜，没用到的不占一行。
    @Test func onlyShotsThatUseHisImagesAreListed() {
        let lines = MetagAssetUse.sentences(for: [
            Self.shot(asset: nil, use: nil),
            Self.shot(asset: 0, use: "reference"),
            Self.shot(asset: nil, use: nil),
        ])
        #expect(lines.count == 1)
    }

    /// 字段真的解得出来 —— 契约名照抄分镜里的，别新造。
    @Test func theContractNamesMatchTheStoryboard() {
        let s = Self.shot(asset: 2, use: "first_frame")
        #expect(s.asset == 2)
        #expect(s.asset_use == "first_frame")
    }
}
