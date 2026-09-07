import Testing
import Foundation
@testable import PalmierPro

/// A gateway call with no caller is a feature nobody can reach.
///
/// This kept happening on both ends today: a web client function sat unused, the converge
/// endpoint shipped with no entry point at all, and `waitForCompletion` here waited for a
/// whole film after we had already switched to filling shots as they land. Each looked
/// correct in isolation, so only a cross-check finds them.
///
/// `EditorActions` needs no equivalent test — it is an `@objc protocol` that
/// `EditorWindowController` conforms to, so a menu item without an implementation does not
/// compile.
@Suite("METAG 网关可达性")
struct MetagReachabilityTests {

    /// Reached from outside the client for reasons the compiler cannot see.
    private static let exempt: Set<String> = [
        "request",              // internal request builder
        // 请求工厂：**七处各造各的 URLRequest 时，加一个头就得改七处，
        // 而漏掉的那一处不会报错 —— 它只是从此匿名。** 收成一个出口之后，
        // 它按定义只在这个文件里被调用。**不设 private 是为了能测**：
        // `ClientTagTests` 断言每个请求都带得出 `X-Metag-Client`，
        // 而网关那侧要靠这个头把 `jobs` 的来源列填出来。
        "urlRequest",           // internal request factory (X-Metag-Client)
        // 判据不许打生产的那道闸：**它按定义只在这个文件里被调用**
        // （七个写路径各调一次）。不设 private 是为了能测 ——
        // `NoProductionWritesUnderTestTests` 直接断言它对七条路都抛。
        // 起因见那条判据的说明：快照测试曾经每跑一次就在生产上建一条真草案。
        "refuseUnderTest",      // internal write gate (判据不许打生产)
        "send",                 // internal transport
        // 204 没有响应体，`send<T: Decodable>` 会试着解 JSON 而必然失败 ——
        // 那会让一次成功的删除看起来像失败。与 send 同类，都是传输原语。
        "sendNoContent",        // internal transport (204 无响应体)
        "currentLanguageCode",  // internal, used while building bodies
        // 与上面几个同类：只被 speak() 调用的内部原语。
        // **它不是 private，是为了能测** —— 拿 WAV 当 .mp3 存，AVFoundation 会
        // 拒绝它，而用户看到的是"配音失败"，与真正的失败无从区分。
        // 那个判断值得一条断言，而断言需要它可见。
        "audioExtension",       // internal, 由 speak() 按响应体魔数选扩展名
        // 同上：只被 highlights() 调用，不设成 private 是为了能测。
        // 一分钟素材的包络是 24000 个点，抽稀写错（比如只取前 200 个）不会报错，
        // 只会让我们"只看了头 0.5 秒"就去找亮点。
        "downsample",           // internal, 由 highlights() 抽稀能量曲线
        // WS 的地址。**按定义只被 `progress(job:)` 调**，不设 private 是为了
        // 能直接断一件安全的事：**这个 URL 里除了票据不许有别的凭证**。
        // 网关那侧已经把 `?token=`（七天 JWT）整条拆掉 —— 而客户端如果放错了，
        // 网关拒了会 401，**而我们有轮询兜底，于是它会变成一个安静的空操作**
        // （网关注释里记着他们自己栽过同款）。判据在 `ProgressStreamTests`。
        "progressURL",          // internal, WS 地址（安全判据要它可见）
    ]

    /// **名单式豁免必须带一条"这个名单还对不对"的判据。**
    ///
    /// ⚠ 2026-09-06 合伙人定的规矩，起因是同一天我们数出的两件事：
    /// 「例外由行为决定，不由名单决定 —— 名单会过期，行为不会」，
    /// 以及**我那天正好用一句注释当过一次例外**（判据不读注释）。
    ///
    /// 上面那两处（`urlRequest` / `refuseUnderTest`）改不成行为式的：
    /// 要豁免的是**符号**，而符号没有"它自己在哪儿"这种可查的性质。
    /// 所以退而求其次 —— **名单里的每个名字，必须还真的是这个文件里的一个出口。**
    ///
    /// 不断这一条的话，改名或删掉其中一个之后：
    /// 那条豁免从此**什么都不豁免**（无害但已是死条目），
    /// 更坏的是**它会静静地豁免掉将来某个同名的新函数** —— 而那才是它变危险的方式。
    @Test func everyExemptionStillNamesSomethingReal() throws {
        let text = try String(contentsOf: gatewaySource, encoding: .utf8)
        // ⚠ 泛型函数是 `func send<T: Decodable>(`，**只匹 `(` 会把它判成不存在**。
        //    这条判据第一次跑就红在 `send` 上 —— 是判据的模式错了，不是名单过期了。
        //    （新判据第一次就红，先怀疑判据自己。）
        let stale = Self.exempt
            .filter { !text.contains("func \($0)(") && !text.contains("func \($0)<") }
            .sorted()
        #expect(stale.isEmpty,
                """
                豁免名单里这几个名字在 MetagGateway.swift 里已经不存在了：\(stale)
                删掉它们 —— 一条死豁免会在将来有人写出同名函数时静静地放过它。
                """)
    }

    private var gatewaySource: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Generation
            .deletingLastPathComponent()   // PalmierProTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sources/PalmierPro/Metag/MetagGateway.swift")
    }

    private func sources(under directory: URL) throws -> [URL] {
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    @Test("MetagGateway 的每个方法都有调用方")
    func everyGatewayCallIsReachable() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Generation
            .deletingLastPathComponent()   // PalmierProTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sources/PalmierPro")
        let client = root.appendingPathComponent("Metag/MetagGateway.swift")

        let declaration = try String(contentsOf: client, encoding: .utf8)
        // **`private static func` 是文件内部的帮手，不该有外部调用方。**
        //
        // 这条判据守的是"做好了没接线的机器"：一个网关方法全仓没人调，
        // 说明那台机器建好了却没接到用户走的那条路上。
        // 而内部帮手（比如 `decode` 那个把 `DecodingError` 收口成兜底文案的）
        // 按定义就只在文件里被调 —— 把它算进来是在惩罚"把重复收敛成一处"。
        let names = declaration
            .replacingOccurrences(of: "private static func ", with: "PRIVATE_HELPER ")
            .components(separatedBy: "static func ")
            .dropFirst()
            .compactMap { chunk -> String? in
                let name = chunk.prefix { $0.isLetter || $0.isNumber }
                return name.isEmpty ? nil : String(name)
            }
            .filter { !Self.exempt.contains($0) }
        #expect(names.count > 5)

        let others = try sources(under: root)
            .filter { $0.lastPathComponent != "MetagGateway.swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        let unreachable = names.filter { !others.contains("MetagGateway.\($0)") }
        #expect(unreachable == [])
    }
}
