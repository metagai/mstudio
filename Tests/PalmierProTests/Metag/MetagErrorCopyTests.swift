import Foundation
import Testing

@testable import PalmierPro

/// 用户看到的必须是**能据此行动**的一句话，不是一个数字。
///
/// 这条规矩一直写在 MetagGateway.Failure 的注释里，而代码只对 `rejected` 兑现了它 ——
/// 其余全部落到 "METAG request failed (404)"。落空的恰恰是最常见的几种：
/// 打开昨天的链接、连点两次出片、传了一张大图、上游抖动。
///
/// 网关会回 15 种状态码，客户端此前只认 4 种。
struct MetagErrorCopyTests {
    /// 普通用户真的会撞到的那几种。
    static let userFacing = [403, 404, 409, 413, 415, 502, 504]

    @Test(arguments: userFacing)
    func commonFailuresSayWhatToDo(code: Int) {
        let text = MetagGateway.Failure.http(code).errorDescription ?? ""
        #expect(!text.isEmpty)
        // 兜底那句话里带着状态码。出现它就说明这一档没有专门的文案。
        #expect(!text.contains("\(code)"), "HTTP \(code) 仍在给用户看裸状态码：\(text)")
    }

    /// 404 同时表示"过期"和"不是你的"。**不能说"已过期"** ——
    /// 那对拿到别人分享链接的人是假话，而假话比含糊更糟。
    @Test func notFoundCopyWorksForBothMeanings() {
        let text = MetagGateway.Failure.http(404).errorDescription ?? ""
        #expect(text.contains("24") || text.contains("gone"))
        #expect(!text.lowercased().contains("expired"))
    }

    /// 没覆盖到的状态码仍要回退到通用文案，而不是崩掉或给空串。
    @Test func unknownCodesStillSaySomething() {
        let text = MetagGateway.Failure.http(418).errorDescription ?? ""
        #expect(!text.isEmpty)
    }
}
