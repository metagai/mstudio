import AppKit
import SwiftUI
import Testing
@testable import PalmierPro

/// **那三行必须在同一条竖线上。**
///
/// 「设置」「反馈」是按钮，「登录」是菜单。`Menu` 用 `.borderlessButton` 时
/// **会缩到标签那么宽然后居中** —— 里面的 `Spacer` 撑不开它。
/// 于是「登录」浮在中间，而上面两行左对齐。
///
/// 这是创始人 2026-09-02 说的「布局问题到处都是」里的一处，
/// 而它长期没被看见，正是因为**取景器画不出 `Menu`**
/// （`ImageRenderer` 对 `Menu` 返回空图，换成 `NSHostingView` 才照得到）。
///
/// 判据量的是**每一行墨迹的左边缘**，不是源码里那个 `.frame` 还在不在。
@Suite("账户浮层那几行对不对齐")
@MainActor
struct PopoverAlignmentTests {
    @Test func everyRowStartsOnTheSameLine() throws {
        let host = NSHostingView(rootView: AccountPopoverCard().frame(width: 300).padding())
        host.frame = CGRect(x: 0, y: 0, width: 332, height: 260)
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)

        // 每一行墨迹从第几列开始。空行跳过。
        var edges: [Int] = []
        for y in stride(from: 0, to: rep.pixelsHigh, by: 1) {
            var first: Int?
            for x in stride(from: 0, to: rep.pixelsWide, by: 1) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                // 底色是纸白；够暗才算墨。
                if c.alphaComponent > 0.5, c.brightnessComponent < 0.55 { first = x; break }
            }
            if let first { edges.append(first) }
        }
        try #require(edges.count > 20, "这一屏几乎没画出东西")

        // 菜单行如果居中，它的左边缘会明显靠右 —— 而"最靠右的那些左边缘"
        // 正是那一行。用分位数看：九成的行应该挤在同一个窄带里。
        let sorted = edges.sorted()
        let p10 = sorted[sorted.count / 10]
        let p90 = sorted[sorted.count * 9 / 10]
        #expect(p90 - p10 < 60,
                "各行左边缘散在 \(p10)–\(p90) 之间 —— 有一行没跟着对齐（多半是那个 Menu）")
    }
}
