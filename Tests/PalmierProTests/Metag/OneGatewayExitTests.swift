import Foundation
import Testing
@testable import PalmierPro

/// **打网关只能有一个出口。**
///
/// ## 为什么光"把它们收进去"不够
///
/// 2026-09-05 我把 `MetagGateway.swift` 里七处手写的 `URLRequest`
/// 收进一个工厂（`urlRequest(_:)`），让每一次调用都带上 `X-Metag-Client`。
/// **收敛完成的那一刻，那个文件里干干净净。**
///
///     我以为的收敛范围   所有打网关的地方
///     实际的收敛范围     **那个文件里**的所有打网关的地方
///
/// 第二天才发现另外两处在别的文件里（`MetagFunnel` 发漏斗事件、
/// `MetagAgentClient` 开 Agent 流），**它们自己造请求，所以不带头**。
/// 那两处是我**碰巧扫到的** —— 而第十处不会有人碰巧扫到。
///
/// ## 它守的那件事，为什么值一条判据
///
/// 网关那侧的来源列把调用分成三种：报了身份的（`web/studio` / `mac/x.y.z` / `mcp`）、
/// `direct`（没报身份）、`(NULL)`（网关那半没生效）。
/// **`direct` 是留给"外面的人"的那一格** —— 我们要靠它回答
/// "有没有人在读我们的公开仓库调接口"。
/// **我们自己漏一个头，那一格就被我们自己污染了**，而这件事不会有任何报错。
///
/// ⚠ 时机也是判据的一部分（partner 提的，比我原来的措辞准）：
/// 不是"新来源列上线的那一刻补上头"，是**在任何新的来源列上线之前**补上 ——
/// 列一上线，从那一秒起写进去的每一行就是脏的，**而脏行不会追溯修复**。
///
/// ⚠ 这条扫源码。例外理由同 `MetagReachabilityTests` / `PriceIsNeverHandBuiltTests`：
/// **要守的性质是"某段代码不存在"，而不存在的东西没有行为可测。**
@Suite("打网关只能有一个出口")
struct OneGatewayExitTests {

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Metag
            .deletingLastPathComponent()   // PalmierProTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sources/PalmierPro")
    }

    private func swiftFiles(under directory: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// 除工厂所在的那个文件外，没有第二处既造 `URLRequest` 又用网关地址。
    @Test func onlyTheFactoryBuildsRequestsForTheGateway() throws {
        let offenders = swiftFiles(under: sourceRoot)
            .filter { $0.lastPathComponent != "MetagGateway.swift" }
            .filter { url in
                guard let s = try? String(contentsOf: url, encoding: .utf8) else { return false }
                return s.contains("URLRequest(") && s.contains("MetagGateway.baseURL")
            }
            .map { $0.lastPathComponent }
        #expect(offenders.isEmpty,
                """
                这些文件自己造了打网关的请求：\(offenders)
                用 `MetagGateway.urlRequest(路径)` —— 它会带上 X-Metag-Client。
                漏了头的调用会落进来源列的 `direct`，而那一格是留给外面的人的。
                """)
    }

    /// 工厂本身还在，且真的会盖那个头。
    /// **不断这一条的话，工厂被删掉之后上面那条会因为无人可查而恒真。**
    @Test func theFactoryStillStampsTheHeader() {
        let req = MetagGateway.urlRequest("api/v1/anything")
        #expect(req.value(forHTTPHeaderField: "X-Metag-Client") == MetagGateway.clientTag)
    }
}
