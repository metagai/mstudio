import Foundation
import Testing
@testable import PalmierPro

/// **生成成功不等于验收通过。**
///
/// 服务端每一镜都打了分（`workers/shot_quality.py`），分数存了库、网关回了、
/// 客户端解了 —— 然后交付那一刻一个字都没说，用户得自己右键某个片段才看得到。
/// 这组判据守的是"说出来"这一步，以及它不许乱说。
@Suite("没通过检查的镜头")
struct FlaggedShotsTests {
    @Test func itFlagsTheShotBelowTheGate() {
        #expect(MetagJobOpener.flaggedShots(scores: [1.0, 0.3, 1.0], delivered: [0, 1, 2]) == [1])
    }

    /// 阈值两侧：正好及格不算坏。
    @Test func itKeepsWhatExactlyPasses() {
        #expect(MetagJobOpener.flaggedShots(scores: [MetagReshoot.qcPass], delivered: [0]).isEmpty)
    }

    /// **没铺上去的镜头不说** —— 说了他在时间线上也找不着那一镜。
    @Test func itIgnoresShotsThatNeverArrived() {
        #expect(MetagJobOpener.flaggedShots(scores: [0.1, 0.1], delivered: [1]) == [1])
    }

    /// 分数缺席 = 没有结论，不是"坏"。服务端抽帧失败时会记 1.00，
    /// 而整格缺失只说明这一镜没被评过。
    @Test func itTreatsAMissingScoreAsNoVerdict() {
        #expect(MetagJobOpener.flaggedShots(scores: [nil, nil], delivered: [0, 1]).isEmpty)
        #expect(MetagJobOpener.flaggedShots(scores: nil, delivered: [0]).isEmpty)
    }

    /// 分数数组比镜头短 —— 越界会崩，而这是服务端给的数据。
    @Test func itSurvivesAShortScoreArray() {
        #expect(MetagJobOpener.flaggedShots(scores: [0.2], delivered: [0, 1, 2]) == [0])
    }

    /// 说出是哪一镜，而且镜号从 1 数起 —— 用户看到的第 1 镜不是第 0 镜。
    @Test func itNamesTheShotOneBased() {
        #expect(MetagJobOpener.flaggedMessage(added: 3, flagged: [1]).contains("2"))
    }
}
