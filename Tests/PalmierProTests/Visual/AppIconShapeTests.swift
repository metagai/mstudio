import AppKit
import Foundation
import Testing
@testable import PalmierPro

/// **图标是他打开产品之前看见的第一样东西。**
///
/// 2026-09-02 之前，`AppIcon.icns` 里每一档都是**直角方块**：
/// 1024 那张的四个角是 `(11,18,16,255)` —— 不透明的黑。
/// 而 macOS 上所有图标都是圆角超椭圆，在画布里内缩一圈、下方压一层阴影。
/// 一个直角方块摆在 Dock 里，是"这个 app 没做完"最早也最显眼的信号。
///
/// 形状不是拍的：拿系统自带 app 的图标、只认完全不透明的像素（避开阴影）
/// 量出来 —— 本体 814×814 / 1024 画布，超椭圆指数 n≈5.1–5.3。
///
/// **量的时候我的眼睛还判错过一次**：并排看觉得自己做的"更圆更胖"，
/// 逐点量完两条轮廓相差不到 1%。数字说了算。
@Suite("app 图标的形状")
struct AppIconShapeTests {
    private static func icon() throws -> NSBitmapImageRep {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PalmierPro/Resources/AppIcon.png")
        let data = try Data(contentsOf: url)
        return try #require(NSBitmapImageRep(data: data))
    }

    /// 四个角必须是透明的 —— 那是"有没有按平台形状裁"最直接的一问。
    @Test func theCornersAreCut() throws {
        let icon = try Self.icon()
        #expect(icon.pixelsWide == 1024 && icon.pixelsHigh == 1024)
        for (x, y) in [(0, 0), (1023, 0), (0, 1023), (1023, 1023)] {
            let alpha = try #require(icon.colorAt(x: x, y: y)).alphaComponent
            #expect(alpha < 0.01, "(\(x),\(y)) 还是不透明的 —— 又变回直角方块了")
        }
    }

    /// 本体大小对齐系统图标：814 上下不超过 2%。
    ///
    /// **只认完全不透明的像素** —— 阴影也有 alpha，算进去会量出一个更大的数。
    @Test func theBodyMatchesTheSystemGeometry() throws {
        let icon = try Self.icon()
        var minX = 1024, maxX = -1
        for x in 0..<1024 {
            for y in 0..<1024 where (icon.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.98 {
                minX = min(minX, x); maxX = max(maxX, x); break
            }
        }
        let body = maxX - minX + 1
        #expect(abs(body - 814) < 17, "本体 \(body)px，系统是 814 —— 摆在 Dock 里大小不是一路的")
    }

    /// 轮廓的圆角量要和系统一路。
    ///
    /// 在 0.85R 高度上量宽度：**直角**方块 1.000，椭圆 0.527，
    /// 系统那条实测 0.892。
    ///
    /// **它分不出圆角矩形和超椭圆** —— 实测两者在这个高度上是
    /// 0.887 对 0.892，差 0.5%，肉眼看不出来。
    /// 变异验的时候把形状换成圆角矩形，这条没红；那不是判据写坏了，
    /// 是我最初的注释吹了它做不到的事（写着"矩形约 1.00"，
    /// 而那说的是直角矩形）。**判据能做到什么就写什么。**
    @Test func theSilhouetteIsRoundedLikeTheSystemOne() throws {
        let icon = try Self.icon()
        var minX = 1024, maxX = -1, minY = 1024, maxY = -1
        for x in 0..<1024 {
            for y in 0..<1024 where (icon.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.98 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        let radius = Double(maxX - minX + 1) / 2
        let centerX = Double(minX + maxX) / 2
        let y = Int((Double(minY + maxY) / 2 + 0.85 * radius).rounded())
        let row = (minX...maxX).filter { (icon.colorAt(x: $0, y: y)?.alphaComponent ?? 0) > 0.98 }
        let width = Double(row.count) / 2 / radius
        #expect(abs(width - 0.892) < 0.05,
                "0.85R 处宽度 \(String(format: "%.3f", width))，系统是 0.892 —— 圆角量差太多，摆在 Dock 里不是一路的")
    }
}
