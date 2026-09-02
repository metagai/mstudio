import Foundation
import Testing
@testable import PalmierPro

/// **他刚看完草案，点"进编辑器"，同一部片子突然轻了一半。**
///
/// `preview.mp4` 最后过了一道 `loudnorm=I=-16`，而时间线是
/// N 段 + 配乐床直接相加、没过 —— 网关那侧**每一单实测**这一档差
/// （`check_editor_hears_the_same_film.py` 量到 5.8 dB），并回在 `master_gain_db` 上。
///
/// Mac 这侧一开始**根本没解这个字段**。我当时的说法是"铺的就是原始文件"——
/// 而产品技术负责人指出：**缺席的默认不是中性，是偏 6 dB 且没人补。**
/// 6 dB 约等于感知响度减半；他不会报这个 bug，他会觉得"这软件声音怪怪的"。
///
/// 判据的形状也是他给的：**别断言"补了多少 dB"，断言"补完之后和草案在同一档"**——
/// 前者在我不读这个字段时永远成立（补了 0，符合预期），后者不会。
@Suite("主音量：和刚播过的那条草案一样响")
struct MasterGainTests {
    /// 草案过了 loudnorm 到 -16；时间线实测低 5.8。补完必须回到同一档。
    @Test func afterTheCorrectionTheTimelineMatchesTheDraft() {
        let draftLUFS = -16.0
        let timelineLUFS = -21.8                   // 实测：低 5.8
        let factor = MetagFilmLayout.volumeFactor(masterGainDB: 5.8)
        let corrected = timelineLUFS + 20 * log10(factor)
        #expect(abs(corrected - draftLUFS) < 0.5,
                "补完是 \(String(format: "%.1f", corrected)) LUFS，草案是 \(draftLUFS)")
    }

    /// **字段缺席时不瞎补**（返回 1）—— 但那不叫"中性"，只叫"不猜"。
    @Test(arguments: [Double?.none, .some(Double.nan), .some(.infinity)])
    func withoutARealNumberItDoesNotGuess(db: Double?) {
        #expect(MetagFilmLayout.volumeFactor(masterGainDB: db) == 1)
    }

    /// 荒谬的数要夹住 —— 宁可少补，也不要把他的片子削顶。
    @Test(arguments: [(100.0, 24.0), (-100.0, -24.0)])
    func absurdValuesAreClamped(given: Double, clampedTo: Double) {
        let expected = pow(10, clampedTo / 20)
        #expect(abs(MetagFilmLayout.volumeFactor(masterGainDB: given) - expected) < 1e-9)
    }

    /// **乘到每一个出声的片段上，配比不变** —— 那正是"主音量"的定义。
    @Test func everyClipMovesTogether() {
        var tracks = [
            Track(type: .video, clips: [Fixtures.clip(start: 0, duration: 30)]),
            Track(type: .audio, clips: [Fixtures.clip(start: 0, duration: 30),
                                        Fixtures.clip(start: 30, duration: 30)]),
        ]
        tracks[1].clips[1].volume = 0.5            // 用户先调低过一段
        MetagFilmLayout.applyMasterGain(2, to: &tracks)
        #expect(tracks[0].clips[0].volume == 2)
        #expect(tracks[1].clips[0].volume == 2)
        #expect(tracks[1].clips[1].volume == 1, "配比被改了 —— 主音量不该重设他自己调过的那一段")
    }

    /// 倍数是 1 的时候一个字节都不该动。
    @Test func aNeutralGainTouchesNothing() {
        var tracks = [Track(type: .audio, clips: [Fixtures.clip(start: 0, duration: 30)])]
        tracks[0].clips[0].volume = 0.3
        MetagFilmLayout.applyMasterGain(1, to: &tracks)
        #expect(tracks[0].clips[0].volume == 0.3)
    }
}
