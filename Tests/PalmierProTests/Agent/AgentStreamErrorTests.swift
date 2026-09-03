import Foundation
import Testing
@testable import PalmierPro

struct AgentServiceErrorTests {
    @Test func envelopeCodeWinsOverStatus() {
        let body = #"{"error":{"code":"insufficient_credits","message":"Out of credits."}}"#
        guard case .insufficientCredits(let message) = AgentServiceError.from(status: 500, body: body) else {
            Issue.record("expected insufficientCredits")
            return
        }
        #expect(message == "Out of credits.")
    }

    @Test(arguments: [(401, true), (402, false)])
    func statusMapsWhenEnvelopeMissing(status: Int, expectsUnauthenticated: Bool) {
        let error = AgentServiceError.from(status: status, body: "")
        if expectsUnauthenticated {
            guard case .unauthenticated = error else {
                Issue.record("expected unauthenticated for \(status)")
                return
            }
        } else {
            guard case .insufficientCredits = error else {
                Issue.record("expected insufficientCredits for \(status)")
                return
            }
        }
    }

    /// body 是空的时候也要有一句人话。
    ///
    /// 这条原来钉着 `message == "HTTP 503"` —— 那正是当时屏幕上写的东西。
    /// 一个纯状态码不是给人看的：他读到它既不知道发生了什么，也不知道该干什么。
    /// 现在钉的是**这句话像话**，不是它逐字长什么样。
    @Test func anEmptyBodyStillGetsASentence() {
        guard case .upstream(let message) = AgentServiceError.from(status: 503, body: "") else {
            Issue.record("expected upstream")
            return
        }
        #expect(message.count > "HTTP 503".count, "503 之后屏幕上只有一个状态码")
        #expect(!message.isEmpty)
    }

    @Test func hostedAgentStaysOffUntilGatewayEndpointShips() {
        // 网关还没有 /api/v1/agent/chat；默认打开会把用户引到一个必然失败的登录 CTA
        #expect(MetagGateway.hostedAgentEnabled == (ProcessInfo.processInfo.environment["METAG_HOSTED_AGENT"] == "1"))
        #expect(MetagAgentClient.path == "api/v1/agent/stream")
    }
}
