import AppKit
import Foundation

/// 粘进（或拖进）prompt 输入框的一份素材。
///
/// **粘一份大纲进来，不该变成一行两千字的输入框；粘一张图进来，不该什么都不发生。**
/// 用户的习惯是复制一个文件然后粘贴 —— 好的做法是把它收成一张卡片，
/// 让他还看得见自己刚写的那一句（创始人 2026-08-31）。
///
/// 稿子是**纯界面**：提交时整段原文照旧并进 `prompt`，不走单独字段。
/// 图片走 `assets` —— `/api/v1/preview` 收它（≤8 张），导演逐镜决定哪张用在哪一镜。
/// **`/api/v1/generate` 不收 `assets`，挂上去会被静默丢掉**，所以素材属于
/// 草案那一步，不是成片那一步。
struct PromptAttachment: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// 一份稿子。整段原文并进 prompt。
        case script(String)
        /// 一张图。上传换 frame_id，作为 `assets` 交给导演。
        case image(URL)
    }

    let id: UUID
    /// 卡片标题。**优先文件名** —— 他拖的是 `第三幕.md`，卡上写 `第三幕.md`
    /// 比写正文第一行更像"我那个文件"。纯粘贴没有文件名才退回取第一行。
    let title: String
    let kind: Kind

    init(id: UUID = UUID(), title: String, kind: Kind) {
        self.id = id
        self.title = title
        self.kind = kind
    }

    var script: String? { if case .script(let t) = kind { t } else { nil } }
    var imageURL: URL? { if case .image(let u) = kind { u } else { nil } }
    var characters: Int? { script?.count }

    /// 卡片上的图标。**一眼看出粘进来的是什么** —— 一份剧本、一份大纲、
    /// 一轨字幕、一张表，长得都不该一样。
    ///
    /// 认剧本靠的是**正文里真的有分镜标记**，不是文件后缀：一个叫
    /// `script.md` 的购物清单不是剧本。
    var symbol: String {
        switch kind {
        case .image: "photo"
        case .script(let text):
            if PromptPaste.shotMarkers(in: text) > 0 { "film.stack" }
            else if title.lowercased().hasSuffix(".srt") || title.lowercased().hasSuffix(".vtt") { "captions.bubble" }
            else if title.lowercased().hasSuffix(".csv") { "tablecells" }
            else if title.lowercased().hasSuffix(".json") { "curlybraces" }
            else if title.lowercased().hasSuffix(".md") || title.lowercased().hasSuffix(".markdown") { "doc.richtext" }
            else if imageURL == nil && !title.contains(".") { "text.quote" }
            else { "doc.text" }
        }
    }

    /// 这份稿子里数得出来的分镜数。**数不出来就不说。**
    var shots: Int? {
        guard let script, case let n = PromptPaste.shotMarkers(in: script), n > 0 else { return nil }
        return n
    }
}

enum PromptPaste {
    /// 超过这么多字就收成卡片。**这是人眼的上限，不是接口的上限** ——
    /// 与 studio 用同一个数，两端对同一段文字的判断必须一致。
    static let cardThreshold = 400

    /// 网关的 `PROMPT_MAX_CHARS`。超了是 400，不是截断 ——
    /// **所以我们要在他按下去之前说，而不是替他砍掉一半。**
    static let promptMaxCharacters = 20_000

    /// 网关的 `MAX_ASSETS`（`GenReq.assets`）。
    static let maxImages = 8

    /// 我们敢当成稿子读的扩展名。**不认的就不认** ——
    /// 把一个 .pdf 按 UTF-8 读出来是一屏乱码，比不接更糟。
    ///
    /// 判据用扩展名不用 MIME：从 Finder 拖出来的 .md 常常没有 type。
    static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "text", "srt", "vtt", "fountain", "csv", "json",
    ]

    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tiff", "tif", "bmp",
    ]

    /// 一个文本文件最多读多少。再大的东西他也不是想当 prompt 用。
    static let fileSizeLimit = 1 << 20  // 1 MB

    /// 收了一部分、没全收下的时候说的那句。
    ///
    /// **不是红条** —— 位置在卡片和输入框之间、灰色小字：这不是错误，
    /// 是"我只收了这些"。（与 studio 用同一套话，两端不许各说各的。）
    enum Notice: Hashable, Sendable {
        case tooManyImages(fit: Int)
        case imageFailed
        case fileUnreadable
        case unsupported

        @MainActor var text: String {
            switch self {
            case .tooManyImages(let fit):
                L10n.string("Only \(fit.formatted()) images fit — the rest weren't added")
            case .imageFailed: L10n.string("Couldn't add that image")
            case .fileUnreadable: L10n.string("Couldn't read that file")
            case .unsupported: L10n.string("Images and text files only")
            }
        }
    }

    struct Outcome: Equatable {
        var attachments: [PromptAttachment] = []
        /// 短句子照常插进输入框。`onPasteCommand` 吃掉了系统的默认粘贴，
        /// 所以这一支要调用方自己补回去。
        var insert: String?
        var notices: [Notice] = []
        /// 剪贴板里没有我们能用的东西。
        var isEmpty: Bool { attachments.isEmpty && insert == nil && notices.isEmpty }
    }

    // MARK: - 剪贴板

    static func read(_ pasteboard: NSPasteboard = .general, existing: [PromptAttachment] = []) -> Outcome {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            return outcome(for: urls, existing: existing)
        }
        // 截图那一类：剪贴板里只有位图，没有文件。落到临时文件才谈得上"附件"。
        for type: NSPasteboard.PasteboardType in [.png, .tiff] {
            guard let data = pasteboard.data(forType: type) else { continue }
            guard let url = writeTemporaryImage(data, ext: type == .png ? "png" : "tiff") else {
                return Outcome(notices: [.imageFailed])
            }
            return outcome(for: [url], existing: existing)
        }
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            return Outcome()
        }
        guard text.count > cardThreshold else { return Outcome(insert: text) }
        return Outcome(attachments: [PromptAttachment(title: title(forFirstLineOf: text), kind: .script(text))])
    }

    /// 拖进来和粘进来走**同一条路、落同一张卡** —— 两个入口给出不同的卡片，
    /// 而用户并不知道自己刚才用的是哪一个。
    static func outcome(for urls: [URL], existing: [PromptAttachment] = []) -> Outcome {
        var out = Outcome()
        var imageBudget = maxImages - existing.filter { $0.imageURL != nil }.count
        var droppedImages = 0
        var sawUnsupported = false

        for url in urls {
            let ext = url.pathExtension.lowercased()
            if imageExtensions.contains(ext) {
                guard imageBudget > 0 else { droppedImages += 1; continue }
                imageBudget -= 1
                out.attachments.append(PromptAttachment(title: url.lastPathComponent, kind: .image(url)))
            } else if textExtensions.contains(ext) {
                if let card = script(contentsOf: url) {
                    out.attachments.append(card)
                } else {
                    out.notices.append(.fileUnreadable)
                }
            } else {
                sawUnsupported = true
            }
        }
        if droppedImages > 0 { out.notices.append(.tooManyImages(fit: maxImages)) }
        if sawUnsupported { out.notices.append(.unsupported) }
        return out
    }

    /// 一个文件能不能当稿子读。读不出 UTF-8 就当读不懂 —— 不猜编码。
    static func script(contentsOf url: URL) -> PromptAttachment? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= fileSizeLimit,
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return PromptAttachment(title: url.lastPathComponent, kind: .script(text))
    }

    private static func writeTemporaryImage(_ data: Data, ext: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pasted-\(UUID().uuidString).\(ext)")
        return (try? data.write(to: url)) == nil ? nil : url
    }

    /// 没有文件名时的标题：正文第一行，截到一行能读完。
    static func title(forFirstLineOf text: String) -> String {
        let line = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let trimmed = line.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : line
        return trimmed.count <= 48 ? trimmed : String(trimmed.prefix(48)) + "…"
    }

    /// 正文里显式写着的分镜标记有几处。
    ///
    /// **只认写出来的，不猜。** 印一个猜出来的镜数比不印更糟 ——
    /// 用户会以为我们已经读懂了这份稿子，而我们只是数了段落。
    /// 认这几种：`SHOT 3` / `CUT TO` / `SCENE 2` / `第 3 镜` / `镜头 4`。
    static func shotMarkers(in text: String) -> Int {
        let patterns = [
            #"^\s*(SHOT|CUT|SCENE)\b"#,
            #"^\s*第\s*\d+\s*[镜场]"#,
            #"^\s*镜头\s*\d+"#,
        ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

        return text.split(separator: "\n", omittingEmptySubsequences: false).count { line in
            let s = String(line)
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            return patterns.contains { $0.firstMatch(in: s, range: range) != nil }
        }
    }

    // MARK: - 提交时

    /// 他打的那一句 + 稿子的原文 = 真正送出去的 prompt。
    /// 顺序是**他写的在前**：卡片是素材，那一句才是他的意图。图片不进这里。
    static func composed(line: String, attachments: [PromptAttachment]) -> String {
        ([line] + attachments.compactMap(\.script))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    static func images(in attachments: [PromptAttachment]) -> [URL] {
        attachments.compactMap(\.imageURL)
    }

    /// 超没超网关那条线。**超了要在他按下去之前说** ——
    /// 替他砍掉一半，他不会知道自己的稿子少了后一半。
    static func overflow(line: String, attachments: [PromptAttachment]) -> Int? {
        let over = composed(line: line, attachments: attachments).count - promptMaxCharacters
        return over > 0 ? over : nil
    }
}
