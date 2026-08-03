import AppKit
import Testing
@testable import PalmierPro

/// 暗色的守卫。
///
/// 这次修的不是"没做暗色"，是**四处窗口代码把外观写死成 `.aqua`**。
/// 所以测试盯的第一件事就是"有没有人又把它钉回去"——那种改动看起来
/// 只是一行，后果却是整个 app 在暗色下瞎掉一半。
@Suite("界面明暗")
struct AppearanceTests {
    private static func sources() -> [(path: String, text: String)] {
        let root = FileManager.default.currentDirectoryPath + "/Sources"
        guard let e = FileManager.default.enumerator(atPath: root) else { return [] }
        var out: [(String, String)] = []
        for case let f as String in e where f.hasSuffix(".swift") {
            if let t = try? String(contentsOfFile: root + "/" + f, encoding: .utf8) {
                out.append((f, t))
            }
        }
        return out
    }

    @Test("没有任何窗口把外观钉死")
    func noPinnedAppearance() {
        let offenders = Self.sources().filter {
            !$0.path.hasSuffix("AppearancePreference.swift")
                && $0.text.contains("NSAppearance(named:")
        }.map(\.path)
        #expect(offenders.isEmpty,
                "这些文件又把外观写死了，暗色会在那里失效：\(offenders)")
    }

    @Test("外观只有一个决定者")
    func singleOwner() {
        let setters = Self.sources().filter {
            !$0.path.hasSuffix("AppearancePreference.swift")
                && ($0.text.contains("NSApp.appearance =") || $0.text.contains("window.appearance ="))
        }.map(\.path)
        #expect(setters.isEmpty,
                "外观应当只由 AppearancePreference 决定；逐处设置意味着每新增一个窗口都要记得设：\(setters)")
    }

    @Test("默认跟随系统，而不是锁亮色")
    func defaultsToAuto() {
        UserDefaults.standard.removeObject(forKey: AppearancePreference.defaultsKey)
        #expect(AppearancePreference.mode == .auto)
        #expect(AppearanceMode.auto.nsAppearance == nil, "auto 必须是「不覆盖」，不是某个具体外观")
    }

    @Test("三种模式各自映射到正确的系统外观")
    func modeMapping() {
        #expect(AppearanceMode.light.nsAppearance?.name == .aqua)
        #expect(AppearanceMode.dark.nsAppearance?.name == .darkAqua)
        #expect(AppearanceMode.allCases.count == 3)
        for m in AppearanceMode.allCases {
            #expect(!m.label.isEmpty)
        }
    }

    @Test("设计 token 在两种外观下取到不同的值")
    func tokensAreDynamic() {
        // 一个 NSColor 自己按外观解析。若某个 token 退回成静态色，
        // 它就会在暗色下留下一块亮色死角 —— 而那种事看编译是看不出来的。
        let light = NSAppearance(named: .aqua)!
        let dark = NSAppearance(named: .darkAqua)!
        func rgb(_ c: NSColor, _ a: NSAppearance) -> [CGFloat] {
            var out: [CGFloat] = [0, 0, 0, 0]
            a.performAsCurrentDrawingAppearance {
                let s = c.usingColorSpace(.sRGB) ?? c
                out = [s.redComponent, s.greenComponent, s.blueComponent, s.alphaComponent]
            }
            return out
        }
        for (name, color) in [("surfaceBase", DesignTokens.surfaceBase),
                              ("contentPrimary", DesignTokens.contentPrimary),
                              ("surfacePanel", DesignTokens.surfacePanel)] {
            #expect(rgb(color, light) != rgb(color, dark), "\(name) 没有跟随外观变化")
        }
    }

    @Test("暗色背景确实更暗、暗色文字确实更亮")
    func darkIsActuallyDark() {
        let light = NSAppearance(named: .aqua)!
        let dark = NSAppearance(named: .darkAqua)!
        func luma(_ c: NSColor, _ a: NSAppearance) -> CGFloat {
            var v: CGFloat = 0
            a.performAsCurrentDrawingAppearance {
                let s = c.usingColorSpace(.sRGB) ?? c
                v = 0.2126 * s.redComponent + 0.7152 * s.greenComponent + 0.0722 * s.blueComponent
            }
            return v
        }
        // 方向搞反过一次就会得到"暗色模式一片惨白"，而那是编译不出来的错
        #expect(luma(DesignTokens.surfaceBase, dark) < luma(DesignTokens.surfaceBase, light))
        #expect(luma(DesignTokens.contentPrimary, dark) > luma(DesignTokens.contentPrimary, light))
    }
}

/// 导出埋点：**只报形状，不报内容**。
///
/// 起因：Web 端已经在报导出事件，Mac 不报的话"有没有人导出过成片"这个数是残的 ——
/// 而那是唯一能回答"产品有没有交付价值"的指标。
@Suite("导出埋点")
struct FilmEventTests {
    @Test("统计里没有任何内容字段")
    func statsCarryNoContent() {
        let s = FilmExportStats(shots: 3, seconds: 12.5, metag: true)
        // 结构体只有三个数。加进片名、提示词、文件路径都会让它变成内容上报，
        // 而隐私政策里公示的是"不含任何内容"。
        #expect(Mirror(reflecting: s).children.count == 3)
        let names = Mirror(reflecting: s).children.compactMap(\.label).sorted()
        #expect(names == ["metag", "seconds", "shots"])
    }

    @Test("帧转秒只有一处口径")
    func framesToSeconds() {
        // 时间线的真源是帧；秒是上报口径。两处各算一遍就会因为 fps 取错而对不上。
        let src = try! String(
            contentsOfFile: FileManager.default.currentDirectoryPath
                + "/Sources/PalmierPro/Export/ExportQueue.swift", encoding: .utf8)
        #expect(src.components(separatedBy: "/ fps").count - 1 == 1,
                "帧转秒出现了不止一处")
    }
}
