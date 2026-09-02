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
    private func snapshot(_ name: String, width: CGFloat = 420,
                          @ViewBuilder _ view: () -> some View) throws {
        let renderer = ImageRenderer(content:
            view()
                .frame(width: width)
                .padding(AppTheme.Spacing.lg)
                .background(AppTheme.Background.baseColor)
        )
        renderer.scale = 2
        let image = try #require(renderer.nsImage, "\(name) 画不出来")
        #expect(image.size.width > 0 && image.size.height > 0, "\(name) 是张空图")
        let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
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
    @Test func home() throws {
        try snapshot("home-hero", width: 720) { HomeHero() }
    }

    /// 「我的作品」—— 今天加了缩略图，一张都没看过。
    @Test func myFilms() throws {
        try snapshot("my-films", width: 640) { MetagMyFilmsView(onOpen: { _ in }) }
    }

    /// 账户浮窗和 credits —— 转化那条路上的两块。
    @Test func account() throws {
        try snapshot("account-popover", width: 320) { AccountPopoverCard() }
        try snapshot("credits", width: 560) { MetagCreditsView() }
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
