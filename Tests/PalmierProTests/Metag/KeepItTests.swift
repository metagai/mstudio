import Foundation
import Testing
@testable import PalmierPro

/// 「留下它」按下去要真的留下来。
///
/// 2026-09-04：漏斗 `exported` 是 **0** —— 20 个人看到自己的片子，
/// 零个把它带走。而那颗按钮此前打开的是 759 行的专业导出面板。
@Suite("留下它")
struct KeepItTests {

    private func folder() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keepit-\(UUID().uuidString)")
    }

    /// **重名不覆盖。** 覆盖掉的是他上一条片子，而他以为自己在存新的那条。
    @Test func aSecondFilmWithTheSameNameDoesNotEatTheFirst() {
        let dir = folder()
        var taken: Set<String> = []
        func nextName() -> String {
            let u = KeepIt.destination(name: "天台上的灯", ext: "mp4", in: dir,
                                       exists: { taken.contains($0.lastPathComponent) })
            taken.insert(u.lastPathComponent)
            return u.lastPathComponent
        }
        #expect(nextName() == "天台上的灯.mp4")
        #expect(nextName() == "天台上的灯 2.mp4")
        #expect(nextName() == "天台上的灯 3.mp4")
    }

    /// 片名来自他那句话，里面什么都可能有。
    /// **`/` 在访达里会变成 `:`**，而一个只剩扩展名的文件他会当成导出失败了。
    @Test func aNameFromHisOwnSentenceStillMakesAFile() {
        let dir = folder()
        let messy = KeepIt.destination(name: "夜里/东京 雨中：一个\"快递员\"",
                                       ext: "mp4", in: dir, exists: { _ in false })
        let name = messy.deletingPathExtension().lastPathComponent
        #expect(!name.contains("/"))
        #expect(!name.contains(":"))
        #expect(!name.contains("\""))
        #expect(!name.isEmpty)
        #expect(messy.pathExtension == "mp4")
    }

    /// 空片名不能生出一个只有扩展名的隐藏文件。
    @Test func anEmptyNameStillLandsSomewhereHeCanSee() {
        let u = KeepIt.destination(name: "   \n ", ext: "mp4", in: folder(), exists: { _ in false })
        let name = u.deletingPathExtension().lastPathComponent
        #expect(!name.isEmpty)
        #expect(!name.hasPrefix("."), "以点开头的文件在访达里是隐藏的 —— 他会以为没存下来")
    }

    /// 文件名有上限，而他那句话可以很长。
    @Test func aVeryLongSentenceDoesNotBlowThePathLimit() {
        let long = String(repeating: "灯", count: 500)
        let u = KeepIt.destination(name: long, ext: "mp4", in: folder(), exists: { _ in false })
        #expect(u.lastPathComponent.utf8.count < 255)
    }

    /// **它进的是漏斗里能被认出来的那一档。**
    /// `exported` 记的是 `source.rawValue`，一次不问参数的保存要能和
    /// "他自己配了参数导的"分开读 —— 否则那一格从 0 变成 1 时我们不知道是哪条路走通了。
    @Test func itIsDistinguishableInTheFunnel() {
        #expect(ExportJobSource.keepIt.rawValue == "keepIt")
        #expect(ExportJobSource.keepIt.rawValue != ExportJobSource.manual.rawValue)
    }
}
