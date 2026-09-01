import Foundation
import Testing
@testable import PalmierPro

/// 首屏的主角是那一句问话。守两件事：**它不许被换回项目列表**，
/// 以及**用户写的那句话必须成为项目名**（列表里那些 `tl-074321` 就是这么来的）。
@Suite("首屏")
struct HomeHeroTests {
    private static func source(_ name: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Home
            .deletingLastPathComponent()   // PalmierProTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // mac
            .appendingPathComponent("Sources/PalmierPro/\(name)")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// 8/29 起 137 个人站在 studio 的输入框前面走了，而 Mac 用户**连输入框都看不到** ——
    /// 首屏是个项目列表。这条盯着输入框排在项目列表前面。
    @Test("首屏第一件事是问他想拍什么")
    func heroComesBeforeTheProjectList() throws {
        let src = Self.source("Home/HomeView.swift")
        let hero = try #require(src.range(of: "HomeHero()"))
        let list = try #require(src.range(of: "MyProjectsSection()"))
        #expect(hero.lowerBound < list.lowerBound, "项目列表排到了输入框前面 —— 那又变回文件管理器了")
    }

    /// 按下去不许弹存储面板。**他要的是片子，不是先给文件起个名。**
    @Test("从一句话开始不弹存储面板")
    func startingAFilmDoesNotAskForAFilename() {
        let src = Self.source("Home/HomeHero.swift")
        #expect(src.contains("AppState.shared.startFilm"))
        #expect(!src.contains("createProjectInteractively"), "首屏又去弹存储面板了")
        #expect(!src.contains("NSSavePanel"))
    }

    /// 项目名用他写的那句话 —— 列表里那些 `tl-074321` 就是没有这一步的后果。
    @Test(arguments: [
        ("a woman in a laundromat", "a woman in a laundromat"),
        ("  两边留白  ", "两边留白"),
        ("带/斜杠\\和:冒号", "带 斜杠 和 冒号"),
        ("连续     空白", "连续 空白"),
        ("...", Project.defaultProjectName),
        ("", Project.defaultProjectName),
    ])
    func projectNameComesFromTheLine(line: String, expected: String) {
        #expect(AppState.projectName(from: line) == expected)
    }

    /// 长句子按**字符**截断，不按字节 —— 中文一句话很短，按字节会砍在半个字上。
    @Test func longLinesAreCutOnCharacterBoundaries() {
        let long = String(repeating: "洗", count: 200)
        let name = AppState.projectName(from: long)
        #expect(name.count <= 48)
        #expect(name.allSatisfy { $0 == "洗" }, "截断把字砍坏了")
    }

    /// 文件名里不能留下路径分隔符 —— 那会让建项目直接抛错，
    /// 而用户只是写了一句带斜杠的话。
    @Test(arguments: ["a/b", "a\\b", "a:b", "../etc/passwd"])
    func projectNameIsAlwaysASafeFilename(line: String) {
        let name = AppState.projectName(from: line)
        #expect(!name.contains("/"))
        #expect(!name.contains("\\"))
        #expect(!name.contains(":"))
        #expect(name != "." && name != "..")
    }
}
