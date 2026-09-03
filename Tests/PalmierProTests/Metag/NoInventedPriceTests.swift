import Foundation
import Testing
@testable import PalmierPro

/// **会花钱的那颗按钮上，不许出现一个我们没有的数字。**
///
/// 一族四颗：出片、批准、克隆音色、买额度。
/// 报价拿不到时上一版各有各的错法 ——
/// 「Approve 0 Credits」（他以为不要钱，然后被扣）、
/// 「Produce · 6 credits」（那是镜数，实扣约 184）。
///
/// 而我在修出片那颗时，注释里写着「导演台和 Web 端都是这么做的」——
/// **导演台并不是。** 说一句没核实的话，就是把错的做法当成了标准答案。
@Suite("价钱不知道的时候按钮上写什么")
struct NoInventedPriceTests {
    private static func labels(_ credits: Int?) -> [(name: String, label: String)] {
        [
            ("出片", MetagDraftSheet.produceLabel(credits: credits)),
            ("批准导演台这一单", MetagDirectorSheet.approveLabel(credits: credits)),
            ("克隆音色", MetagVoiceSheet.cloneLabel(credits: credits)),
        ]
    }

    /// 不知道价钱 → 一个数字都不许有。
    @Test func anUnknownPriceNeverPrintsANumber() {
        for (name, label) in Self.labels(nil) {
            #expect(!label.isEmpty, "\(name)：价钱不知道时按钮上一个字都没有")
            let hasDigit = label.rangeOfCharacter(from: .decimalDigits) != nil
            #expect(!hasDigit,
                    "\(name)：价钱不知道，按钮上却印了个数 —— 「\(label)」")
        }
    }

    /// 知道价钱 → 必须印出来，别为了躲上面那条把价钱也藏了。
    @Test func aKnownPriceIsAlwaysShown() {
        for (name, label) in Self.labels(180) {
            #expect(label.contains("180"), "\(name)：报价回来了却没印在按钮上 —— 「\(label)」")
        }
    }
}
