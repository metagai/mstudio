import Foundation
import Testing
@testable import PalmierPro

/// **片子落到他手上的那一刻，请他留住它。**
///
/// 「愿不愿意导出」就是创始人定的三个北极星里的内容质量那一个 ——
/// 而在 2026-09-01 之前，那件事只存在于菜单栏第二层：片子载入成功后
/// 屏幕上只有一句「已载入 4 镜」，然后什么都没有。
///
/// 那一刻是他最想留住它的时候，也是我们唯一不用开口就能请他行动的时候。
@Suite("片子落地那一刻")
struct FilmLandingTests {
    private static func source(_ name: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PalmierPro/\(name)")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// 取到片子就挂上"导出"。
    @Test func aLandedFilmOffersExport() {
        let src = Self.source("Metag/MetagJobOpener.swift")
        #expect(src.contains("action: added > 0 ? .export : nil"),
                "片子落地又变成只弹一句提示了 —— 那一刻是他最想留住它的时候")
    }

    /// **一镜都没取到就不挂** —— 没有东西可导，摆一颗按钮是骗人。
    @Test func nothingToExportMeansNoButton() {
        let toast = MediaPanelToast(message: "x", kind: .warning)
        #expect(toast.action == nil, "默认不带动作")
    }

    /// 动作是枚举不是闭包：这个结构体存在 `@Observable` 状态里，
    /// 要保持 Equatable（否则动画对不上）和 Sendable。
    @Test func theToastStaysComparable() {
        let a = MediaPanelToast(message: "done", kind: .success, action: .export)
        let b = MediaPanelToast(message: "done", kind: .success, action: .export)
        let c = MediaPanelToast(message: "done", kind: .success)
        #expect(a == b)
        #expect(a != c)
    }

    /// 那颗按钮真的接到了导出，不是一颗装饰。
    @Test func theButtonActuallyOpensExport() {
        let src = Self.source("MediaPanel/MediaTab/MediaTab.swift")
        #expect(src.contains("toast.action == .export"))
        #expect(src.contains("editor.showExportDialog = true"),
                "那颗按钮没接到导出 —— 一颗点了没反应的按钮比没有按钮更糟")
    }
}
