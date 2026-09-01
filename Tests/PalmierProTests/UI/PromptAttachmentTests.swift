import AppKit
import Foundation
import Testing
@testable import PalmierPro

/// **粘一份大纲进来，不该变成一行两千字的输入框；粘一张图进来，不该什么都不发生。**
///
/// 创始人 2026-08-31：「用户会习惯 copy 文本文件（或图片），然后 paste 进来，
/// 好的体验应该是以附件形式展示」。查下来 Mac 上五个 prompt 输入框里只有
/// Agent 对话框接了粘贴，其余四个（含首页和一键成片）粘什么都不会发生。
@Suite("粘进来的素材")
struct PromptAttachmentTests {
    private static func temporaryFile(_ name: String, _ contents: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("attach-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - 该收成卡片的和不该收的

    /// 每个测试一块**自己的**剪贴板。系统剪贴板是全局的，
    /// 并行跑测试会互相踩 —— 而且我们不该动用户正在用的那一块。
    private static func pasteboard(_ contents: String) -> NSPasteboard {
        let pb = NSPasteboard(name: .init("PromptAttachmentTests-\(UUID().uuidString)"))
        pb.clearContents()
        pb.setString(contents, forType: .string)
        return pb
    }

    /// 短句子照常插进输入框 —— 一句话不该变成附件。
    @Test func shortTextGoesStraightIntoTheField() {
        let outcome = PromptPaste.read(Self.pasteboard("a woman folds laundry"))
        #expect(outcome.insert == "a woman folds laundry")
        #expect(outcome.attachments.isEmpty)
    }

    /// 超过 400 字收成卡片。**这个数和 studio 是同一个** ——
    /// 两端对同一段文字的判断必须一致。
    @Test func aLongPasteBecomesACard() {
        let script = String(repeating: "镜头缓缓推近。", count: 80)   // 远超 400
        let outcome = PromptPaste.read(Self.pasteboard(script))
        #expect(outcome.insert == nil, "一份大纲被塞进了单行输入框")
        #expect(outcome.attachments.count == 1)
        #expect(outcome.attachments.first?.script == script)
    }

    /// 正好在线上不收，线外一个字就收 —— 阈值本身也要被咬住。
    @Test(arguments: [(400, false), (401, true)])
    func theThresholdBitesExactly(count: Int, becomesCard: Bool) {
        let outcome = PromptPaste.read(Self.pasteboard(String(repeating: "a", count: count)))
        #expect(!outcome.attachments.isEmpty == becomesCard)
    }

    @Test func theThresholdMatchesStudio() {
        #expect(PromptPaste.cardThreshold == 400)
        #expect(PromptPaste.promptMaxCharacters == 20_000)
        #expect(PromptPaste.maxImages == 8)
    }

    // MARK: - 文件

    /// 文本文件的标题用**文件名**，不是正文第一行 ——
    /// 他拖的是 `第三幕.md`，卡上就该写 `第三幕.md`。
    @Test func aTextFileKeepsItsName() throws {
        let url = try Self.temporaryFile("第三幕.md", "# 第三幕\n她把最后一件衣服叠好。")
        let outcome = PromptPaste.outcome(for: [url])
        #expect(outcome.attachments.first?.title == "第三幕.md")
        #expect(outcome.attachments.first?.script?.contains("她把最后一件衣服叠好") == true)
    }

    /// 纯粘贴没有文件名，才退回取正文第一行。
    @Test func pastedTextFallsBackToItsFirstLine() {
        #expect(PromptPaste.title(forFirstLineOf: "第三幕\n她把最后一件衣服叠好。") == "第三幕")
    }

    /// **读不懂的不认。** 把一个 .pdf 按 UTF-8 读出来是一屏乱码，比不接更糟。
    @Test(arguments: ["deck.pdf", "clip.mov", "sheet.xlsx"])
    func unsupportedFilesSaySoInsteadOfVanishing(name: String) throws {
        let url = try Self.temporaryFile(name, "not really that format")
        let outcome = PromptPaste.outcome(for: [url])
        #expect(outcome.attachments.isEmpty)
        #expect(outcome.notices.contains(.unsupported), "不认的文件被静默吞掉了")
    }

    /// 图片按扩展名认，不按 MIME —— 从 Finder 拖出来的常常没有 type。
    @Test(arguments: ["a.png", "b.JPG", "c.heic", "d.webp"])
    func imagesAreRecognisedByExtension(name: String) throws {
        let url = try Self.temporaryFile(name, "x")
        #expect(PromptPaste.outcome(for: [url]).attachments.first?.imageURL == url)
    }

    // MARK: - 上限：**收不下的要说，不许沉默**

    /// 网关的 `MAX_ASSETS` 是 8。第 9 张收不下 —— 而收不下要说出来。
    @Test func theNinthImageIsRefusedOutLoud() throws {
        let urls = try (1...9).map { try Self.temporaryFile("shot\($0).png", "x") }
        let outcome = PromptPaste.outcome(for: urls)
        #expect(outcome.attachments.count == 8)
        #expect(outcome.notices.contains(.tooManyImages(fit: 8)),
                "多的几张被静默丢掉了 —— 他会以为我们收下了")
    }

    /// 已经有 8 张了，再粘一张也要说。**预算要算上已经在卡片里的那些。**
    @Test func theBudgetCountsWhatIsAlreadyThere() throws {
        let existing = try (1...8).map {
            PromptAttachment(title: "s\($0).png", kind: .image(try Self.temporaryFile("s\($0).png", "x")))
        }
        let more = try Self.temporaryFile("extra.png", "x")
        let outcome = PromptPaste.outcome(for: [more], existing: existing)
        #expect(outcome.attachments.isEmpty)
        #expect(outcome.notices.contains(.tooManyImages(fit: 8)))
    }

    // MARK: - 提交时兑现

    /// 他写的那一句在前，稿子在后 —— 卡片是素材，那一句才是他的意图。
    @Test func hisLineComesFirst() {
        let card = PromptAttachment(title: "outline.md", kind: .script("SHOT 1. 洗衣房。"))
        #expect(PromptPaste.composed(line: "拍成黑白的", attachments: [card])
                == "拍成黑白的\n\nSHOT 1. 洗衣房。")
    }

    /// 只有稿子、没打字也能成立 —— 他拖进来一份剧本就是他的意图。
    @Test func aScriptAloneIsEnough() {
        let card = PromptAttachment(title: "outline.md", kind: .script("SHOT 1."))
        #expect(PromptPaste.composed(line: "", attachments: [card]) == "SHOT 1.")
    }

    /// 图片不并进 prompt —— 它走 `assets`。
    @Test func imagesNeverLandInThePrompt() {
        let img = PromptAttachment(title: "ref.png", kind: .image(URL(fileURLWithPath: "/tmp/ref.png")))
        #expect(PromptPaste.composed(line: "一句话", attachments: [img]) == "一句话")
        #expect(PromptPaste.images(in: [img]).count == 1)
    }

    // MARK: - 卡片上说什么

    /// **镜数只在稿子里真写着的时候才说。**
    ///
    /// 猜一个数字印上去，他会以为我们已经读懂了这份剧本 —— 那比不印更糟。
    @Test(arguments: [
        ("SHOT 1. 洗衣房。\nSHOT 2. 街道。\nSHOT 3. 天台。", 3),
        ("第 1 镜 洗衣房\n第 2 镜 街道", 2),
        ("镜头 1 洗衣房\n镜头 2 街道\n镜头 3 天台\n镜头 4 车站", 4),
        ("CUT TO: 街道\nSCENE 2", 2),
    ])
    func aScriptWithRealMarkersSaysHowManyShots(text: String, expected: Int) {
        let card = PromptAttachment(title: "script.md", kind: .script(text))
        #expect(card.shots == expected)
        #expect(card.symbol == "film.stack", "认出来是剧本了，图标却还是一张白纸")
    }

    /// 没有标记就**一个字都不说** —— 一份购物清单不是四镜片子。
    @Test(arguments: [
        "她把最后一件衣服叠好。\n午后的光斜进来。\n滚筒还在转。\n窗外有车经过。",
        "牛奶\n鸡蛋\n面包",
        "",
    ])
    func aPlainNoteNeverClaimsShots(text: String) {
        #expect(PromptAttachment(title: "notes.md", kind: .script(text)).shots == nil,
                "我们数了段落，然后把它当成镜数印在了卡片上")
    }

    /// **认剧本靠正文，不靠后缀。** 一个叫 `script.md` 的购物清单不是剧本。
    @Test func theNameAloneNeverMakesItAScript() {
        let fake = PromptAttachment(title: "script.md", kind: .script("牛奶\n鸡蛋"))
        #expect(fake.shots == nil)
        #expect(fake.symbol != "film.stack")
    }

    /// 一眼看出粘进来的是什么 —— 几种东西不该长得一样。
    @Test(arguments: [
        ("lines.srt", "00:00:01 --> 00:00:03", "captions.bubble"),
        ("data.csv", "a,b,c", "tablecells"),
        ("shots.json", "{}", "curlybraces"),
        ("outline.md", "# 大纲", "doc.richtext"),
    ])
    func eachKindGetsItsOwnIcon(name: String, body: String, symbol: String) {
        #expect(PromptAttachment(title: name, kind: .script(body)).symbol == symbol)
    }

    @Test func anImageIsAlwaysAnImage() {
        let img = PromptAttachment(title: "ref.png", kind: .image(URL(fileURLWithPath: "/tmp/ref.png")))
        #expect(img.symbol == "photo")
        #expect(img.shots == nil)
    }

    /// **超了要在他按下去之前说**，不是替他砍掉后一半。
    @Test func overLimitIsReportedNotTruncated() {
        let huge = PromptAttachment(
            title: "book.md",
            kind: .script(String(repeating: "字", count: PromptPaste.promptMaxCharacters + 25))
        )
        #expect(PromptPaste.overflow(line: "", attachments: [huge]) == 25)
        #expect(PromptPaste.composed(line: "", attachments: [huge]).count
                == PromptPaste.promptMaxCharacters + 25,
                "内容被悄悄截断了 —— 他不会知道自己的稿子少了后一半")
    }

    @Test func withinTheLimitThereIsNothingToSay() {
        #expect(PromptPaste.overflow(line: "一句话", attachments: []) == nil)
    }
}
