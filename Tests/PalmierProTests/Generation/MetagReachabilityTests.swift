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
    ]

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
        let names = declaration
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
