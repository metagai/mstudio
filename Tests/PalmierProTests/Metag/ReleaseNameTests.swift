import Foundation
import Testing
@testable import PalmierPro

/// **发出去的那个包，名字只能有一处定义。**
///
/// ## 2026-09-06 它咬了 0.1.17
///
///     scp 传上去的        METAG-0.1.17-mac.dmg
///     appcast 告诉用户的   METAG-0.1.17.dmg      ← 少了 `-mac`
///
/// 两处各拼一遍，**每个用户的自动更新指向一个不存在的文件**。
/// 签名过、公证过、启动活过 8 秒、DMG 传上去了 —— 整条流水线只有最后
/// 那条回验发现了它，而那时东西已经公开了。
///
/// ⚠ 更值得记的是：出事那一行**上面就写着**
/// 「名字只有一处定义，"三处一致"不再需要判据，它是构造上成立的」。
/// **那句话说得准，也没拦住任何东西** —— 一句只出现在人读得到的地方的判断，
/// 不是判据，是备忘。这一条就是把那句备忘变成判据。
///
/// ⚠ 这条扫源码。例外理由同 `PriceIsNeverHandBuiltTests`：
/// **要守的性质是"某段代码不存在第二处"，而不存在的东西没有行为可测。**
@Suite("包名只有一处定义")
struct ReleaseNameTests {

    private var releaseScript: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Metag
            .deletingLastPathComponent()   // PalmierProTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("scripts/release.sh")
    }

    /// 拼包名的地方只能有一处。
    ///
    /// ⚠ **注释行要跳过，而这不是偷懒**：合伙人同一天栽过一次同款 ——
    /// 他那条判据咬了**讲它自己那个坑的那句注释**。而上面那段账里就写着
    /// `METAG-{v}.dmg`，不跳过的话这条判据会因为自己的说明而红。
    /// 他那句结论一起记下：**「文件里出现过这个字符串」和「有人这样拼它」之间，
    /// 永远还有下一种载体。** 这里的载体只有 `#`（shell 和内嵌 Python 都是它）。
    @Test func theDMGNameIsBuiltInExactlyOnePlace() throws {
        let lines = try String(contentsOf: releaseScript, encoding: .utf8)
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        let builders = lines.filter { line in
            line.contains("METAG-") && (line.contains("$VERSION") || line.contains("{v}"))
        }
        #expect(builders.count == 1,
                """
                拼包名的地方不止一处：
                \(builders.joined(separator: "\n"))
                名字只能由 REMOTE_DMG 一处定义 —— 两处各拼一遍的那次，
                appcast 指向了一个不存在的文件，每个用户的自动更新拿到 404。
                """)
    }

    /// 那一处必须真的叫 `REMOTE_DMG` —— 否则下面几处引用会各自散开。
    @Test func thatOnePlaceIsTheSharedVariable() throws {
        let src = try String(contentsOf: releaseScript, encoding: .utf8)
        #expect(src.contains("REMOTE_DMG=\"METAG-$VERSION-mac.dmg\""),
                "REMOTE_DMG 不见了或改了形状 —— appcast、scp、R2/OSS 三处会重新散开")
        #expect(src.contains("os.environ[\"REMOTE_DMG\"]"),
                "appcast 那段又开始自己拼名字了")
    }
}
