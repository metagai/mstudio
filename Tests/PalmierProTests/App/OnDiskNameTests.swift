import Foundation
import Testing
@testable import PalmierPro

/// **我们在他硬盘上占的那个文件夹，他会看见。**
///
/// 设置里的「储存空间」一屏把这几条路径原样列出来，而在这之前它们写的是
/// `~/Library/Caches/PalmierPro` —— 一个他从没听说过的名字，
/// 出现在他刚装的这个 app 的设置里。（2026-09-02 创始人指出。）
///
/// 一共**六处**落盘位置，此前各写各的字面量：缓存、转写、模型、LUT、
/// 示例工程、MCP 令牌，外加崩溃日志。**一处一份名字，加第七处的时候又会漂。**
///
/// 判据比的是**真实的 URL**，不是源码里有没有那个字符串 ——
/// 换个写法（拼接、插值、常量）绕过字符串判据太容易了。
@Suite("硬盘上那个名字")
struct OnDiskNameTests {
    /// 每一条用户看得见的路径都不许带旧名字。
    @Test(arguments: [
        ("缓存根", DiskCache.rootDirectory),
        ("转写", TranscriptCache.directory),
        ("模型", ModelDownloader.modelsDir),
        ("MCP 令牌", MCPAccessToken.fileURL),
        ("Application Support 根", AppIdentity.applicationSupportRoot),
    ])
    func noPathCarriesTheOldName(what: String, url: URL) {
        #expect(!url.path.contains("PalmierPro"),
                "\(what) 还在 \(url.path) —— 他在「储存空间」里会看到一个没听说过的名字")
        #expect(url.path.contains(AppIdentity.directoryName),
                "\(what) 落在 \(url.path)，没带上产品名")
    }

    /// 它们**共用同一个根**。各自拼各自的名字，迟早有一处漂掉。
    @Test func everythingSharesOneRoot() {
        for url in [DiskCache.rootDirectory, TranscriptCache.directory] {
            #expect(url.path.hasPrefix(AppIdentity.cachesRoot.path),
                    "\(url.path) 不在缓存根底下 —— 「储存空间」那一屏统计不到它")
        }
        for url in [ModelDownloader.modelsDir, MCPAccessToken.fileURL] {
            #expect(url.path.hasPrefix(AppIdentity.applicationSupportRoot.path))
        }
    }
}
