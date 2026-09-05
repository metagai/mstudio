import AppKit
import SwiftUI
import Testing
@testable import PalmierPro

/// **把屏幕渲染成图，好让人真的看一眼。**
///
/// 2026-09-01：一整天的界面改动，一处都没被人看过 —— `screencapture` 认
/// bundle 身份，而后台会话没有。于是"我改好了"全靠源码里那几行断言撑着，
/// 而断言只知道那一行在不在，不知道它长什么样。
///
/// `ImageRenderer` 在进程内画，不需要任何权限、不用摆窗口、
/// 不用驱动鼠标（合成点击会落进别人正在打字的窗口）。
///
/// **这不是判据，是取景器。** 它只保证画得出来（不崩、不空白）；
/// 好不好看由人看图决定 —— 图落在 `.build/snapshots/`。
@Suite("界面快照")
@MainActor
struct ViewSnapshots {
    private static let outputDirectory: URL = {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/snapshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// 画一张，落盘，并且**确认它不是一张空白** —— 渲染失败最常见的样子
    /// 不是崩溃，是一张什么都没有的图，而那种图看起来像"这一屏还没做"。
    /// 画一张，落盘，并且**确认它不是一张空白**。
    ///
    /// ## 为什么是 `NSHostingView` 而不是 `ImageRenderer`
    ///
    /// `ImageRenderer` 有两个硬限制，而它们正好盖住了这个产品最要紧的两块：
    ///
    /// | | ImageRenderer | NSHostingView |
    /// |---|---|---|
    /// | 裸文字 | 1430 | 2414 |
    /// | **`ScrollView` 里的东西** | **0** | 2414 |
    /// | **`Menu` 里的东西** | **画不出** | 2593 |
    ///
    /// 编辑器几乎每块面板都套着 `ScrollView`，侧栏那一行登录是个 `Menu` ——
    /// 2026-09-02 创始人发的四张截图里，有两处问题我**只能对着像素猜**，
    /// 就是因为取景器画不出它们。换成 AppKit 这条路之后两处都照得到。
    ///
    /// （量的时候先栽了一次：`cacheDisplay` 出来是透明位图，
    /// 而"透明"的 brightness 是 0，于是每个像素都被算成深色，
    /// 三种情形返回同一个数 —— **一个成功了却什么都没量到的测量**。
    /// 底色给白的才量得准。）
    /// 把一个视图画成位图。
    ///
    /// **快照和"量像素"那几条判据走同一套构图** —— 各搭各的话，
    /// 判据量到的坐标和落盘那张图对不上，而人看的是那张图。
    /// （第一版就是这样：判据不带内边距，扫出九档左边缘，而图上只有一档。）
    private func render(_ view: some View, width: CGFloat) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: AnyView(
            view
                .frame(width: width)
                .padding(AppTheme.Spacing.lg)
                .background(AppTheme.Background.baseColor)))
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    private func snapshot(_ name: String, width: CGFloat = 420,
                          @ViewBuilder _ view: () -> some View) throws {
        let bitmap = try render(view(), width: width)
        #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0, "\(name) 是张空图")

        // **一张纯色的图也是"画出来了"。**
        //
        // 上一版只断言尺寸大于零 —— 于是 `AudioPanelTab` 没有工程时
        // 一笔都不画，取景器照样报绿。二十张全空掉，闸也是绿的：
        // **一台什么都没拍到的相机，比没有相机更糟**。
        //
        // 判据是"这张图上有几种颜色" —— 一屏界面不可能只有一种。
        // 阈值 4 是量过的：全空 1 种、底加边框 1 种、加一个字 2 种，
        // 而真实截图里最少的一张（credits-loaded）是 11 种。两边都有余量。
        var seen = Set<UInt32>()
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      c.alphaComponent > 0.5 else { continue }
                seen.insert(UInt32(c.redComponent * 31) << 10
                    | UInt32(c.greenComponent * 31) << 5 | UInt32(c.blueComponent * 31))
            }
        }
        #expect(seen.count >= 4, "\(name) 只有 \(seen.count) 种颜色 —— 这一屏什么都没画出来")

        let data = try #require(bitmap.representation(
            using: NSBitmapImageRep.FileType.png,
            properties: [NSBitmapImageRep.PropertyKey: Any]()))
        try data.write(to: Self.outputDirectory.appendingPathComponent("\(name).png"))
    }

    /// 等片子的那道幕布 —— 今天改成"槽位数 = 真实镜数"，没人看过。
    @Test func filmStrip() throws {
        let swatch = NSImage(size: CGSize(width: 160, height: 90), flipped: false) { rect in
            NSColor.systemIndigo.setFill(); rect.fill(); return true
        }
        // **三个状态各画一张。** 只看中间那张，会错过他真正盯得最久的
        // 第一张 —— 头三十秒屏幕上一格画面都没有。
        try snapshot("film-strip-0") {
            MetagFilmStrip(shots: 5, frames: [:], narrations: [
                "天台的门被推开，风灌了进来。",
                "她站在边上，没有往下看。",
                "远处的城市亮着，一格一格。",
                "他追上来的时候，她已经笑了。",
                "两个人就那样站着，谁也没说话。",
            ])
        }
        try snapshot("film-strip-2") { MetagFilmStrip(shots: 5, frames: [0: swatch, 1: swatch]) }
        try snapshot("film-strip-5") {
            MetagFilmStrip(shots: 5, frames: Dictionary(uniqueKeysWithValues: (0..<5).map { ($0, swatch) }))
        }
    }

    /// **空格子里必须是那句旁白，不是格子的编号。**
    ///
    /// 2026-09-01 渲出来看了一眼：他按下出片后头三十秒盯着的，是五个
    /// 写着 1 2 3 4 5 的空盒子 —— 而那正是他说"这期间能做点缓解等待的
    /// Aha 效果吧"之后我给的答案。旁白当时就在同一个调用点上。
    ///
    /// 判据是**画出来的两张图不一样**，不是源码里有没有那个变量：
    /// 传了旁白还画得跟没传一模一样，就说明它根本没被用上。
    @Test func theWaitShowsHisStoryNotSlotNumbers() throws {
        func pixels(_ narrations: [String]) throws -> Data {
            let renderer = ImageRenderer(content:
                MetagFilmStrip(shots: 3, frames: [:], narrations: narrations).frame(width: 420))
            let image = try #require(renderer.nsImage)
            return try #require(image.tiffRepresentation)
        }
        let numbered = try pixels([])
        let story = try pixels(["天台的门被推开。", "她没有往下看。", "远处的城市亮着。"])
        #expect(numbered != story,
                "空格子里画的还是编号 —— 那三十秒他看的是五个空盒子，不是自己的故事")

        // 网关还没写到后面几镜的时候，那几格**退回编号**，不是一片空白。
        let partial = try pixels(["天台的门被推开。"])
        #expect(partial != numbered && partial != story,
                "分镜只写了一半时，剩下的格子要么全空了，要么整块没在跟着走")
    }

    /// 他决定花不花这笔钱的那一屏。**转化全在这里，而我没看过它。**
    @Test func draftSheet() throws {
        try snapshot("draft-sheet", width: 560) {
            MetagDraftSheet(initialPrompt: "一个女孩在天台上看城市的灯一格一格亮起来")
                .environment(EditorViewModel())
        }
    }

    /// **首屏。** 除了那句问话，它是常驻的东西 —— 而侧栏底部那两行今天刚重画过。
    /// **首屏那一排真片子。**
    ///
    /// 一个视频产品，第一屏原来一帧画面都没有 —— 三行写死的例句，
    /// 点一下开拍，而那条路的 Aha 隔着九十秒。
    @Test func showcase() throws {
        let root = URL(string: "https://metag.ai")!
        let films = [
            MetagShowcase(id: "second-take", line: "第一遍不对，就再来一遍。",
                          poster: root.appendingPathComponent("media/sc-second-poster.jpg"),
                          reel: root.appendingPathComponent("media/sc-second.mp4"), aspect: 16.0 / 9),
            MetagShowcase(id: "cat", line: "一句话，20 秒一镜到底。",
                          poster: root.appendingPathComponent("media/sc-cat-poster.jpg"),
                          reel: root.appendingPathComponent("media/sc-cat.mp4"), aspect: 16.0 / 9),
            MetagShowcase(id: "pizza", line: "最后 3 秒，甲方出现了。",
                          poster: root.appendingPathComponent("media/sc-pizza-poster.jpg"),
                          reel: root.appendingPathComponent("media/sc-pizza.mp4"), aspect: 720.0 / 1280),
        ]
        try snapshot("showcase-strip", width: 720) { MetagShowcaseStrip(films: films) }
    }

    /// **他等的那九十秒。** 分镜先到、首帧后到，中间他看的是什么。
    @Test func theWait() throws {
        let narrations = [
            "天台的门被推开，风灌进来。",
            "她没有往下看，只是把手放在栏杆上。",
            "远处的城市一格一格亮起来。",
            "楼下有人按了喇叭，她笑了一下。",
            "最后一盏灯亮起时，她转身下楼。",
        ]
        try snapshot("wait-story", width: 560) {
            MetagFilmStrip(shots: 5, frames: [:], narrations: narrations)
        }
        let swatch = NSImage(size: NSSize(width: 160, height: 90), flipped: false) { rect in
            NSColor.systemIndigo.setFill(); rect.fill(); return true
        }
        try snapshot("wait-first-frames", width: 560) {
            MetagFilmStrip(shots: 5, frames: [0: swatch, 1: swatch], narrations: narrations)
        }
    }

    @Test func home() throws {
        try snapshot("home-hero", width: 720) { HomeHero() }
        // **侧栏底部那两行。** 创始人 2026-09-02 真机量出来：
        // 「登录」的图标比其余三行左 8.5pt。那一行是个 `Menu`，
        // 而 `ImageRenderer` 画不出 `Menu` —— 换成 NSHostingView 才照得到。
        try snapshot("home-sidebar", width: 900) { HomeView() }
    }

    /// 「我的作品」—— 今天加了缩略图，一张都没看过。
    @Test func myFilms() throws {
        // 首屏那一格：他上一条片子。测试里没有真视频，所以这里看的是
        // **占位那一刻的样子** —— 而那正是他网慢时会看到的第一眼。
        let lastFilm = try JSONDecoder().decode(MetagGateway.FilmRow.self, from: Data("""
        {"job_id":"a","status":"done","engine":"local","shots":3,"credits":30,
         "created_at":1000,"prompt":"一个女孩在天台上看城市的灯一格一格亮起来",
         "retrievable":true,"refunded":false,"poster":"shot_0.mp4"}
        """.utf8))
        try snapshot("last-film", width: 400) { LastFilm(film: lastFilm, onOpen: {}) }
        try snapshot("my-films", width: 640) { MetagMyFilmsView(onOpen: { _ in }) }
    }

    /// **引导四屏。**
    ///
    /// 此前只有第一屏可能被人看过 —— 要看第四屏得先答完问卷。
    /// 而第四屏是他刚装完 app 看到的第一样东西，也是转化的第一道门。
    @Test func onboarding() throws {
        for step in [OnboardingStep.account] {
            let store = OnboardingStore(defaults: UserDefaults(
                suiteName: "onboarding-shot-\(UUID().uuidString)")!)
            store.jumpForTesting(to: step)
            try snapshot("onboarding-\(step)", width: AppTheme.Onboarding.cardWidth) {
                // **不替它定高度** —— 登录屏现在自己贴着内容长，
                // 外面钉一个数就看不出它到底长多高了。
                OnboardingOverlay(onboarding: store)
            }
        }
    }

    /// **登录按钮上的字不许竖起来。**
    ///
    /// 2026-09-02 创始人装完真机截图：四颗登录按钮的字全折成了两行 ——
    /// WeC/hat、App/le、Goo/gle、Git/Hub。原因是 `accountAction` 按竖排设计，
    /// 却被塞进了 footer 那个 `HStack`：六颗按钮加一句赠额文字挤在一行里放不下，
    /// provider 按钮被压到最窄。**而这一屏是新用户看到的第一样东西。**
    ///
    /// 判据是**把窗子挤窄，这一屏的高度不许变** —— 折行的唯一表现就是变高。
    /// 比断言"源码里有 lineLimit"结实：那句在不在，和字会不会竖起来是两件事。
    @Test func theSignInButtonsNeverStackTheirLetters() throws {
        func height(width: CGFloat) throws -> Int {
            let store = OnboardingStore(defaults: UserDefaults(
                suiteName: "onboarding-wrap-\(UUID().uuidString)")!)
            store.jumpForTesting(to: .account)
            let renderer = ImageRenderer(content:
                OnboardingOverlay(onboarding: store).frame(width: width))
            renderer.scale = 1
            return Int(try #require(renderer.nsImage).size.height)
        }
        let roomy = try height(width: AppTheme.Onboarding.cardWidth)
        let cramped = try height(width: AppTheme.Onboarding.cardWidth * 0.55)
        #expect(roomy == cramped,
                "挤窄之后这一屏从 \(roomy) 变成 \(cramped) —— 按钮上的字折行了")
    }

    /// **对话框按它说的话定大小。**
    ///
    /// 420 是四屏共用的一个数：欢迎屏有一张 240pt 的图撑得住，
    /// 登录屏只有标题加一行字，中间空掉一半 —— 读起来就是"没做完"。
    @Test func theAccountCardDoesNotLeaveAVoid() throws {
        func height(_ step: OnboardingStep) throws -> Int {
            let store = OnboardingStore(defaults: UserDefaults(
                suiteName: "onboarding-void-\(UUID().uuidString)")!)
            store.jumpForTesting(to: step)
            let renderer = ImageRenderer(content:
                OnboardingOverlay(onboarding: store).frame(width: AppTheme.Onboarding.cardWidth))
            renderer.scale = 1
            return Int(try #require(renderer.nsImage).size.height)
        }
        #expect(try height(.account) < Int(AppTheme.Onboarding.cardHeight),
                "登录屏还是四屏共用那个高度 —— 中间空掉一半")
    }

    // **侧栏对齐这条判据，两次都没做成，第二次的原因值得留下。**
    //
    // 第一次删掉是因为 `ImageRenderer` 画不出 `Menu` —— 它永远看不见那个错位。
    // 换成 `NSHostingView` 之后 `Menu` 画得出来了（实测 2593 个深色像素），
    // 于是再写了一次：整列扫像素、把图标左边缘聚类、要求只有一档。
    //
    // **变异前后都是 [26, 34]pt 两档** —— 也就是说它量的根本不是那 8.5pt。
    // 因为四行的图标是四个不同的字形（`plus` / `folder` /
    // `person.crop.circle` / `gearshape`），**每个字形在自己的框里
    // 左侧留白都不一样**。
    //
    // > **量墨迹回答不了"框对不对齐"。**
    //
    // 同一个坑我今天在别处踩过一次：拿创始人截图量两个组标题的缩进，
    // 7pt 和 10pt，而那是 `chevron.down` 和 `chevron.right` 的字形差，
    // 不是布局差。
    //
    // 要真守住这一条，得去问**框**而不是墨 ——
    // 遍历 `NSHostingView` 的子视图树、比图标那几个 `NSView` 的 frame。
    // 那是另一块活，记在这里，不在这一轮硬凑。
    // 那 8.5pt 的修复本身（`.menuStyle(.button)`）已由创始人真机截图确认。

    /// **有货的那一版。**
    ///
    /// 2026-09-02：这一天照的头几屏几乎全是「正在载入」——
    /// **空屋子里藏不住东西**。等片子那三十秒是五个空盒子，
    /// **编辑器的面板 —— 这个产品真正的主场。**
    ///
    /// 2026-09-02 创始人发了一张编辑器截图说"布局问题到处都是"，
    /// 而我只能对着截图量像素猜，因为这一块进不了取景器。
    ///
    /// ⚠ **取景器看不进 `ScrollView`** —— `ImageRenderer` 在里面画的是
    /// **零个像素**（实测：裸文字 1430 个深色像素，套一层之后 0，
    /// `scrollDisabled(true)` 和给死高度都救不了）。
    /// 而编辑器几乎每块面板都套着一层。所以照的是**里面那几节**。
    @Test func editorPanels() throws {
        // 空工程的面板一笔都不画 —— 和「我的作品」只照到「正在载入」是同一个坑。
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [
            Fixtures.videoTrack(clips: [Fixtures.clip(start: 0, duration: 90)]),
        ])
        // 检视器：他在编辑器里待最久的那一块。
        // 换成 NSHostingView 之后 `ScrollView` 里的东西照得到了，
        // 所以这里照的是**整块面板**，不用再把内容抠出来。
        try snapshot("panel-inspector", width: 330) {
            InspectorView().environment(editor)
        }
        try snapshot("panel-music", width: 330) {
            MusicSection(isExpanded: .constant(true)).environment(editor)
        }
        try snapshot("panel-speech", width: 330) {
            SpeechAnalysisSections(silenceExpanded: .constant(true),
                                   speakerExpanded: .constant(false))
                .environment(editor)
        }
    }

    /// 是喂了真数据之后才看见的。
    @Test func loadedStates() throws {
        let now = Date().timeIntervalSince1970
        try snapshot("my-films-loaded", width: 640) {
            MetagMyFilmsView(onOpen: { _ in }, model: MetagMyFilmsModel(preloaded: [
                .init(job_id: "j1", status: "done", engine: "seedance", shots: 5,
                      credits: 120, created_at: now - 600,
                      prompt: "一个女孩在天台上看城市的灯一格一格亮起来",
                      retrievable: true, refunded: nil, poster: "shot_0.mp4"),
                // **长 prompt 是常态不是异常** —— 创始人在 web 端粘过两千字。
                .init(job_id: "j2", status: "done", engine: "veo", shots: 8,
                      credits: 640, created_at: now - 86_400,
                      prompt: String(repeating: "他站在那里很久，什么也没说。", count: 40),
                      retrievable: true, refunded: nil, poster: "shot_0.mp4"),
                // 取件过期：**扣了钱却打不开**，这一行必须如实标出来。
                .init(job_id: "j3", status: "done", engine: "local", shots: 3,
                      credits: 30, created_at: now - 3 * 86_400,
                      prompt: "夜里的东京雨中，一个快递员骑车穿过街道",
                      retrievable: false, refunded: nil, poster: nil),
                // 失败并退款。
                .init(job_id: "j4", status: "failed", engine: "seedance", shots: 4,
                      credits: 96, created_at: now - 7 * 86_400,
                      prompt: nil, retrievable: false, refunded: true, poster: nil),
            ]))
        }
        try snapshot("credits-loaded", width: 360) {
            MetagCreditsView(model: MetagCreditsModel(preloaded: [
                .init(at: now - 300, reason: "generate", delta: -120, job_id: "j1",
                      title: "一个女孩在天台上看城市的灯"),
                .init(at: now - 3600, reason: "refund_lost_artifact", delta: 96, job_id: "j4",
                      title: nil),
                .init(at: now - 86_400, reason: "purchase", delta: 2000, job_id: nil, title: nil),
                .init(at: now - 30 * 86_400, reason: "signup", delta: 300, job_id: nil, title: nil),
            ]))
        }
    }

    /// 账户浮窗和 credits —— 转化那条路上的两块。
    @Test func account() throws {
        try snapshot("account-popover", width: 320) { AccountPopoverCard() }
        // 它自己就是 360 宽 —— 按别的宽度渲，看到的居中是取景器的锅，不是产品的。
        try snapshot("credits", width: 360) { MetagCreditsView() }
    }

    /// **导演组。** 创始人点名要过的那段仪式感 —— 而我从来没看过它。
    ///
    /// 六个人各画一张：每一张是他在那六十秒里某一刻**真正看到的那一屏**。
    @Test func crew() throws {
        for member in MetagCrew.members {
            try snapshot("crew-\(member.stage)", width: 560) {
                MetagCrewView(stage: member.stage, shotCount: 5)
            }
        }
        // 还没开始的那一刻：一个人都不该亮。
        try snapshot("crew-idle", width: 560) { MetagCrewView(stage: nil, shotCount: nil) }
    }

    /// **这一排必须看得出片子过了几手。**
    ///
    /// 2026-09-01 六个阶段各渲一张才发现：「什么都没开始」和
    /// 「六个人里五个交接完了」两张图放一起，差别只有一个圈的位置 ——
    /// 经手过的人是 `Opacity.subtle`（**4%**），等于没上色。
    /// 他盯着这块看九十秒，看到的是一排静止的灰圆点。
    ///
    /// **仪式感的本质是累积。**
    ///
    /// 判据量的是**屏幕上真上了多少颜色**，不是"两张图一不一样"。
    /// 第一版比的是图片字节：4% 透明度和填实画出来的字节当然不同，
    /// 于是把那 4% 原样改回去它照样绿 —— **量了"有没有变"，
    /// 而要问的是"看不看得见"**。今天第三条空绿的判据。
    @Test func theCrewStripAccumulates() throws {
        /// 一张图里有多少像素是**真上了色的**（够饱和、不是灰底也不是描边）。
        func inked(_ stage: String?) throws -> Int {
            let renderer = ImageRenderer(content:
                MetagCrewView(stage: stage, shotCount: 5).frame(width: 560))
            renderer.scale = 1
            let image = try #require(renderer.nsImage)
            let data = try #require(image.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: data))
            var count = 0
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
                for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                    guard let c = bitmap.colorAt(x: x, y: y) else { continue }
                    var (h, sat, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
                    c.usingColorSpace(.sRGB)?.getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
                    if sat > 0.35, b > 0.25, a > 0.5 { count += 1 }
                }
            }
            return count
        }

        let idle = try inked(nil)
        let done = try inked(MetagCrew.members.last?.stage)
        // 一个人都没交活的时候，屏幕上不该有成片的颜色。
        #expect(idle < 40, "还没开始就已经上了 \(idle) 个彩色像素")
        // **绝对下限，不是"比 idle 多几倍"。**
        // 第一版写的是 `done > idle * 8`，而 idle 是 0 —— 乘 0 的阈值等于没有阈值，
        // 把 4% 原样改回去照样绿。实测：填实 539，4% 只有 33
        // （那 33 是正在干活那位的描边，跟"交完活的人上没上色"无关）。
        #expect(done > 300,
                "五个人交接完，屏幕上才 \(done) 个彩色像素 —— 这一排不累积，他盯九十秒看到的是一排灰点")
    }

    /// **导出。** 北极星第二条（他愿不愿意把片子留下）就落在这一屏，
    /// 而它从来没被人看过。
    @Test func export() throws {
        try snapshot("export", width: 980) {
            ExportView().environment(EditorViewModel())
        }
    }

    /// 模型列表 —— 今天加了一句话简介和每镜价，还有四个空状态，都没看过。
    @Test func modelsPane() throws {
        try snapshot("models-pane", width: 560) { ModelsPane() }
    }

    /// 粘进来的稿子摆成卡片。**长短两种、图片一张**，一起看才知道它们像不像一套。
    @Test func promptAttachments() throws {
        try snapshot("prompt-attachments") {
            PromptAttachmentBar(
                attachments: .constant([
                    PromptAttachment(
                        title: "第三幕 · 天台.md",
                        kind: .script("SHOT 1\n天台，黄昏。\nSHOT 2\n她推开门。\nSHOT 3\n远处的城市。")),
                    PromptAttachment(
                        title: "Pasted text",
                        kind: .script(String(repeating: "他站在那里很久。", count: 60))),
                ]),
                notices: [.tooManyImages(fit: 8)]
            )
        }
    }
}
