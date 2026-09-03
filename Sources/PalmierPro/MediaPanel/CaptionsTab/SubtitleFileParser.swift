import Foundation
import UniformTypeIdentifiers

/// A subtitle cue timed in timeline seconds, with markup already stripped.
struct SubtitleCue: Equatable, Sendable {
    /// 一个词和它的时间。**秒制** —— 帧要到铺进时间线那一步才知道。
    struct Word: Equatable, Sendable {
        var text: String
        var startSeconds: Double
        var endSeconds: Double
    }

    var text: String
    var startSeconds: Double
    var endSeconds: Double
    /// 词级时间。SRT / WebVTT 里没有这个，所以是可选的；
    /// **METAG 的片子自带**（网关那侧逐句合成时就对齐好了），
    /// 有了它卡拉OK 那套模板才有东西可放。
    ///
    /// 给已有的类型加一层可选能力，而不是另开一个"带词的 cue" ——
    /// 两个类型就会有两条铺字幕的路，而它们迟早不一样。
    var words: [Word]?
}

/// Parses SRT and WebVTT subtitle files into plain-text cues.
enum SubtitleFileParser {
    enum Format: Sendable {
        case srt, webVTT

        init?(fileExtension: String) {
            switch fileExtension.lowercased() {
            case "srt": self = .srt
            case "vtt": self = .webVTT
            default: return nil
            }
        }
    }

    enum ParseError: LocalizedError, Equatable {
        case unsupportedFileType(String)
        case missingWebVTTHeader
        case malformedCue(line: Int)
        case noCues

        /// **机器那一侧的错误串 —— 不许本地化。**
        ///
        /// 它同时是 `add_captions` 这个 MCP 工具的错误输出，而 AGENTS.md 写着
        /// 「Agent 与 MCP 契约、持久化值、稳定标识、机器可读错误一律不本地化」。
        /// 2026-09-02 我把它翻译了，`rejectsCombinedOptionsWrongTypesAndMalformedFiles`
        /// 当场红 —— 判据是对的：**契约稳定和界面说人话是两件事，要两份。**
        var errorDescription: String? {
            switch self {
            case .unsupportedFileType(let ext): "Unsupported subtitle file type “.\(ext)”. Use SRT or WebVTT."
            case .missingWebVTTHeader: "Not a WebVTT file — the WEBVTT header is missing."
            case .malformedCue(let line): "Malformed cue timing at line \(line)."
            case .noCues: "The file contains no captions."
            }
        }

        /// **人那一侧的那句话。** 在界面边界上用它（SubtitlePreviewView），
        /// 每一句都说清他**能做什么** —— 「做不到」后面要跟一条「你可以」。
        @MainActor
        var userMessage: String {
            switch self {
            case .unsupportedFileType(let ext):
                L10n.string("“.\(ext)” isn’t a subtitle file we can read — use .srt or .vtt.")
            case .missingWebVTTHeader:
                L10n.string("This .vtt file is missing its WEBVTT header — re-export it, or try the .srt version.")
            case .malformedCue(let line):
                L10n.string("The timing on line \(line) doesn’t look right — fix that line and drop it in again.")
            case .noCues:
                L10n.string("There are no captions in this file.")
            }
        }
    }

    static var contentTypes: [UTType] {
        ["srt", "vtt"].compactMap { UTType(filenameExtension: $0) }
    }

    @concurrent
    static func parseFile(at url: URL) async throws -> [SubtitleCue] {
        guard let format = Format(fileExtension: url.pathExtension) else {
            throw ParseError.unsupportedFileType(url.pathExtension)
        }
        let data = try Data(contentsOf: url)
        // Latin-1 decodes any byte sequence, so non-UTF-8 files still parse.
        let contents = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        return try parse(contents, format: format)
    }

    static func parse(_ contents: String, format: Format) throws -> [SubtitleCue] {
        var normalized = contents
        if normalized.hasPrefix("\u{FEFF}") { normalized.removeFirst() }
        let lines = normalized
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        // Blank-line-separated blocks, tagged with their 0-based starting line.
        var blocks: [(start: Int, lines: [String])] = []
        for (index, line) in lines.enumerated() where !line.isEmpty {
            if let last = blocks.indices.last, blocks[last].start + blocks[last].lines.count == index {
                blocks[last].lines.append(line)
            } else {
                blocks.append((index, [line]))
            }
        }
        if format == .webVTT {
            guard let header = blocks.first?.lines.first, isKeywordLine(header, keyword: "WEBVTT") else {
                throw ParseError.missingWebVTTHeader
            }
            blocks.removeFirst()
        }

        var cues: [SubtitleCue] = []
        for block in blocks {
            if format == .webVTT, ["NOTE", "STYLE", "REGION"].contains(where: { isKeywordLine(block.lines[0], keyword: $0) }) {
                continue
            }
            // The timing line may be preceded by one SRT index or WebVTT cue-identifier line.
            guard let timingIndex = block.lines.prefix(2).firstIndex(where: { $0.contains("-->") }) else {
                throw ParseError.malformedCue(line: block.start + 1)
            }
            let sides = block.lines[timingIndex].components(separatedBy: "-->")
            guard sides.count == 2, let start = seconds(in: sides[0]), let end = seconds(in: sides[1]),
                  end > start else {
                throw ParseError.malformedCue(line: block.start + timingIndex + 1)
            }
            var textLines: [String] = []
            for (offset, line) in block.lines.enumerated().dropFirst(timingIndex + 1) {
                guard !line.contains("-->") else {
                    throw ParseError.malformedCue(line: block.start + offset + 1)
                }
                let stripped = plainText(line)
                if !stripped.isEmpty { textLines.append(stripped) }
            }
            let text = textLines.joined(separator: "\n")
            if !text.isEmpty {
                cues.append(SubtitleCue(text: text, startSeconds: start, endSeconds: end))
            }
        }
        guard !cues.isEmpty else { throw ParseError.noCues }
        return cues.sorted { $0.startSeconds < $1.startSeconds }
    }

    private static func isKeywordLine(_ line: String, keyword: String) -> Bool {
        line == keyword || line.hasPrefix(keyword + " ") || line.hasPrefix(keyword + "\t")
    }

    /// `HH:MM:SS.mmm` and `MM:SS.mmm` with `.` or `,` milliseconds. Trailing WebVTT cue
    /// settings and SRT coordinate extensions are ignored. The digit bounds keep the
    /// largest expressible time (< 10,000 h) safely inside frame-count `Int` math.
    private static func seconds(in token: String) -> Double? {
        let pattern = /(?:(\d{1,4}):)?([0-5]?\d):([0-5]?\d)[.,](\d{1,3})(?=\s|$)/
        guard let match = token.trimmingCharacters(in: .whitespaces).prefixMatch(of: pattern) else {
            return nil
        }
        let hours = match.1.flatMap { Int($0) } ?? 0
        guard let minutes = Int(match.2), let seconds = Int(match.3), let fraction = Int(match.4) else {
            return nil
        }
        let milliseconds = fraction * [100, 10, 1][match.4.count - 1]
        return Double(hours) * 3600 + Double(minutes) * 60 + Double(seconds) + Double(milliseconds) / 1000
    }

    static func plainText(_ line: String) -> String {
        var text = line.replacing(/<[^>]*>|\{[^}]*\}/, with: "")
        // `&amp;` decodes last so `&amp;lt;` yields the literal `&lt;`.
        for (entity, value) in [
            ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", "\u{00A0}"),
            ("&lrm;", "\u{200E}"), ("&rlm;", "\u{200F}"), ("&amp;", "&"),
        ] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
}
