import Foundation
import Testing

@testable import PalmierPro

/// METAG 的界面里不许有写死的中文。
///
/// 2026-08-04 复查时，草案面板上有 9 处、额度流水 3 处、我的作品 4 处 ——
/// 也就是说英文和西语用户在**决定要不要花钱的那一屏**看到的是一屏中文。
/// 产品对外承诺三种语言，而最关键的转化屏只有一种。
///
/// 这条检查扫的是源码而不是运行时：SwiftUI 的 `Text("字面量")` 在运行时
/// 与 `Text(L("..."))` 长得一模一样，只有在源码上才分得出来。
struct MetagLocalizationTests {
    private static let metagDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Metag
        .deletingLastPathComponent()   // PalmierProTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // mac
        .appendingPathComponent("Sources/PalmierPro/Metag")

    @Test func noHardcodedChineseInUserFacingText() throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: Self.metagDir, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }
        // 目录找不到就该红，不该"没有文件所以通过" —— 静默跳过的检查等于没有检查。
        #expect(files.count > 5, "没扫到 Metag 源码，路径变了？")

        var offenders: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let s = String(line)
                // 注释里的中文是给我们看的，不是给用户看的
                if s.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                guard let range = s.range(of: #"(Text|Button|Label)\("[^"]*[\u{4e00}-\u{9fff}]"#,
                                          options: .regularExpression) else { continue }
                offenders.append("\(file.lastPathComponent):\(i + 1)  \(s[range])")
            }
        }
        // 清单只能 print：#expect 的第二个参数要静态注释，而这份清单是动态的。
        if !offenders.isEmpty {
            print("写死的中文（应当走 L(...)）：")
            offenders.forEach { print("  " + $0) }
        }
        #expect(offenders == [])
    }
}
