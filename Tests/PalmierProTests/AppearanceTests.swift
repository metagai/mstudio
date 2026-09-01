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
            !$0.path.hasSuffix("AppAppearance.swift")
                && $0.text.contains("NSAppearance(named:")
        }.map(\.path)
        #expect(offenders.isEmpty,
                "这些文件又把外观写死了，暗色会在那里失效：\(offenders)")
    }

    @Test("外观只有一个决定者")
    func singleOwner() {
        let setters = Self.sources().filter {
            !$0.path.hasSuffix("AppAppearance.swift")
                && ($0.text.contains("NSApp.appearance =") || $0.text.contains("window.appearance ="))
        }.map(\.path)
        #expect(setters.isEmpty,
                "外观应当只由 AppAppearance 决定；逐处设置意味着每新增一个窗口都要记得设：\(setters)")
    }

    @Test("默认跟随系统，而不是锁亮色")
    func defaultsToAuto() {
        let defaults = UserDefaults(suiteName: "appearance-default-test")!
        defaults.removeObject(forKey: AppAppearance.defaultsKey)
        #expect(AppAppearance.stored(in: defaults) == .system)
        #expect(AppAppearance.system.nsAppearance == nil, "system 必须是「不覆盖」，不是某个具体外观")
    }

    @Test("三种模式各自映射到正确的系统外观")
    func modeMapping() {
        #expect(AppAppearance.light.nsAppearance?.name == .aqua)
        #expect(AppAppearance.dark.nsAppearance?.name == .darkAqua)
        #expect(AppAppearance.allCases.count == 3)
        for m in AppAppearance.allCases {
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

/// 引导流程（上游 94394bb）拿进来时的适配守卫。
///
/// 照抄上游最危险的不是编译错误 —— 那会当场发现。危险的是**照抄了一句
/// 我们兑现不了的承诺**：上游文案写着"登录送 250 free credits"，
/// 而我们的赠额是网关的 signup_free_credits（当前 20）。
/// 那句话会出现在产品的第一屏。
@Suite("引导流程")
struct OnboardingAdaptationTests {
    private static func source(_ name: String) -> String {
        (try? String(contentsOfFile: FileManager.default.currentDirectoryPath
            + "/Sources/PalmierPro/Home/Onboarding/\(name)", encoding: .utf8)) ?? ""
    }

    @Test("赠额不写死 —— 它来自网关的定价端点")
    func freeCreditsAreNotHardcoded() {
        // **只查字符串字面量，不查注释。** 第一版直接 contains("250")，
        // 结果被我自己写的"不要照抄上游的 250"那句注释判红 ——
        // 断言太粗会训练人忽略它。
        // 赠额那句从 Steps 挪到了 Overlay —— 它挂在登录按钮旁边，
        // 因为它是登录的理由，不是打开 app 的理由。
        let src = Self.source("OnboardingOverlay.swift")
        let literals = src.split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        #expect(!literals.contains("250 free"), "又出现了写死的赠额数字")
        #expect(src.contains("signup_free_credits"),
                "赠额没有取自定价端点 —— 网关是单一真源")
        // 取不到时不提数字，宁可少说一句也不要说错一个数
        // 第一屏先说他能立刻得到什么：不登录也能先看一眼。
        #expect(Self.source("OnboardingSteps.swift").contains("No account needed for the first look."))
    }

    @Test("品牌名已换成 METAG")
    func brandIsOurs() {
        for f in ["OnboardingSteps.swift", "OnboardingModels.swift", "OnboardingOverlay.swift"] {
            #expect(!Self.source(f).contains("Palmier Pro"), "\(f) 里还留着上游品牌名")
        }
    }

    @Test("选项存的是 key，不是已本地化的字符串")
    func modelsStoreKeys() {
        // 在类型初始化时本地化会让**切换语言不生效**（静态常量只算一次）。
        // 字段名就叫 labelKey，语义必须对得上。
        let src = Self.source("OnboardingModels.swift")
        #expect(src.contains("labelKey: \"other\"") || src.contains("labelKey: \"Other\""),
                "选项标签不再是裸 key")
        #expect(!src.contains("L(\""), "Models 里不该本地化 —— 渲染处才调 L()")
    }

    @Test("引导文案在三种界面语言里都有")
    func copyIsTranslated() {
        // L10n 只暴露 en / zh-Hans / es；缺翻译会退回英文，
        // 而"欢迎来到 METAG"是中文用户看到的第一句话。
        for lang in ["en", "zh-Hans", "es"] {
            let path = FileManager.default.currentDirectoryPath
                + "/Sources/PalmierPro/Resources/Localization/\(lang).lproj/Localizable.strings"
            let table = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            for key in ["Welcome to METAG", "What best describes your role?",
                        "Sign in to start generating."] {
                #expect(table.contains("\"\(key)\""), "\(lang) 缺文案：\(key)")
            }
        }
    }

    /// **第一屏的主按钮不是登录。**
    ///
    /// 8/29 起 1112 个人落地、0 个人打过一行字 —— 而他们在这一屏看到的最响的
    /// 一句话是"用 Google 登录"。陌生人本来就能建草案（网关放行），
    /// 墙在"想出片"那一步。这条盯着它不许被换回去。
    @Test("第一屏先给他看片子，不是先要身份")
    func firstScreenLeadsWithTheProduct() {
        let src = Self.source("OnboardingOverlay.swift")
        let primary = src.range(of: "primaryButton(L10n.string(\"See your film first\")")
        let signIn = src.range(of: "Sign in with Google")
        #expect(primary != nil, "第一屏的主按钮不再是「先看一眼」")
        if let primary, let signIn {
            #expect(primary.lowerBound < signIn.lowerBound,
                    "登录排在了「先看一眼」前面 —— 那就又变回一堵墙了")
        }
    }
}
