import Foundation

private final class BundledResourceToken {}

enum BundledResource {
    private static let bundleName = "PalmierPro_PalmierPro.bundle"

    /// 资源包可能在的几个地方，**按可信度排**。
    ///
    /// 三种跑法三个形状，而它们都是真实存在的跑法：
    ///
    /// - `swift test`：token 在 `…/debug/PalmierProPackageTests.xctest` 里，
    ///   资源包是它的**兄弟** —— 所以要往上一级找。
    /// - `swift run`：token 就在可执行文件里，`bundleURL` 是 `…/debug` 这个**目录**，
    ///   资源包在它**里面** —— 往上一级就找过头了。
    /// - 打好包的 `.app`：`bundle.sh` 把 `.lproj` 摊平到了 app 根部，走 `.main`。
    ///
    /// **原来只有第一条。** 于是 `swift run` 拿不到资源包，悄悄回落到 `.main` ——
    /// 而 `.main` 里一个 `.lproj` 都没有：设置里的语言下拉框**只剩一个
    /// "System Language"**，系统语言是中文的机器上 app 照样一屏英文，
    /// 而且没有任何地方能改。2026-08-31 创始人的机器就是这样。
    ///
    /// 它不报错、不崩溃，英文用户看不出任何异常 —— 这是它活到今天的原因。
    static func candidates(token: URL, main: URL, mainResources: URL?) -> [URL] {
        let roots: [URL?] = [
            token.deletingLastPathComponent(),  // .xctest 的兄弟
            token,                              // swift run：可执行文件所在目录
            main,
            mainResources,
        ]
        return roots.compactMap { $0?.appendingPathComponent(bundleName) }
    }

    static let bundle: Bundle = {
        guard Bundle.main.bundleURL.pathExtension != "app" else { return .main }
        let found = candidates(
            token: Bundle(for: BundledResourceToken.self).bundleURL,
            main: Bundle.main.bundleURL,
            mainResources: Bundle.main.resourceURL
        )
        .first { FileManager.default.fileExists(atPath: $0.path) }
        return found.flatMap(Bundle.init(url:)) ?? .main
    }()

    static func url(_ path: String) -> URL? {
        let inBundles = candidates(
            token: Bundle(for: BundledResourceToken.self).bundleURL,
            main: Bundle.main.bundleURL,
            mainResources: Bundle.main.resourceURL
        )
        .map { $0.appendingPathComponent(path) }
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent(path)].compactMap { $0 } + inBundles
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
