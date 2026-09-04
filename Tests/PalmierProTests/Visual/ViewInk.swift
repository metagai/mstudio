import AppKit
import SwiftUI
import Testing
@testable import PalmierPro

/// 把一个视图画成位图，然后问它**屏幕上有什么**。
///
/// ## 为什么要有这一处
///
/// 2026-09-03：六个测试文件各自手搓同一套
/// `NSHostingView` + `cacheDisplay` + 逐像素循环，其中三份是同一天加的。
/// 各写一份的代价当天就来了 ——
///
/// 我那条"账户浮层几行对不对齐"找的是**浅底上的深色墨迹**
/// （`brightness < 0.55`）。换到暗色外观之后一个像素都匹配不到，
/// 于是它在一个**完全正常的界面上判红**（见第四十二条：
/// 乱红的判据死得比不红的更快）。
///
/// 而 `ViewSnapshots` 里那份从一开始就铺了已知底色 —— **答案早就在仓库里**，
/// 我没找就自己写了一遍。
///
/// ## 它给的三样
///
/// | | 回答的问题 |
/// |---|---|
/// | `bitmap` | 画出来 |
/// | `litPixels` | **屏幕上有没有东西**（"这一块是不是空的"） |
/// | `leftEdges` | **每一行墨迹从第几列开始**（"这几行对不对齐"） |
///
/// 后两样都拿**和底色的反差**说话，不拿绝对亮度 —— 外观会变，反差不会。
enum ViewInk {
    /// 底色铺成和取景器同一张 —— **判据量到的和落盘那张图必须是同一个构图**。
    @MainActor
    static func bitmap(of view: some View, width: CGFloat,
                       padding: CGFloat = AppTheme.Spacing.lg) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: AnyView(
            view
                .frame(width: width)
                .padding(padding)
                .background(AppTheme.Background.baseColor)))
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    /// 和底色差得够远的像素有多少个。**问的是"看不看得见"，不是"有没有变"。**
    ///
    /// （比字节、比两张图一不一样都答不了这个问题 ——
    /// 4% 透明度和填实画出来的字节当然不同。）
    static func litPixels(_ bitmap: NSBitmapImageRep, contrast: CGFloat = 0.12, step: Int = 2) -> Int {
        var lit = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: step) {
            guard let base = brightness(bitmap, 1, y) else { continue }
            for x in stride(from: 0, to: bitmap.pixelsWide, by: step) {
                guard let b = brightness(bitmap, x, y) else { continue }
                if abs(b - base) > contrast { lit += 1 }
            }
        }
        return lit
    }

    /// 每一行墨迹从第几列开始。空行不计。
    static func leftEdges(_ bitmap: NSBitmapImageRep, contrast: CGFloat = 0.25) -> [Int] {
        var edges: [Int] = []
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 1) {
            // 最左那一列当本行底色 —— 内容不会画到内边距外面去。
            guard let base = brightness(bitmap, 1, y) else { continue }
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 1) {
                guard let b = brightness(bitmap, x, y) else { continue }
                if abs(b - base) > contrast { edges.append(x); break }
            }
        }
        return edges
    }

    private static func brightness(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat? {
        guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
              c.alphaComponent > 0.5 else { return nil }
        return c.brightnessComponent
    }
}
