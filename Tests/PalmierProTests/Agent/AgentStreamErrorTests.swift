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

    @Test func unknownStatusFallsBackToStatusText() {
        guard case .upstream(let message) = AgentServiceError.from(status: 503, body: "") else {
            Issue.record("expected upstream")
            return
        }
        #expect(message == "HTTP 503")
    }

    @Test func hostedAgentStaysOffUntilGatewayEndpointShips() {
        // 网关还没有 /api/v1/agent/chat；默认打开会把用户引到一个必然失败的登录 CTA
        #expect(MetagGateway.hostedAgentEnabled == (ProcessInfo.processInfo.environment["METAG_HOSTED_AGENT"] == "1"))
        #expect(MetagAgentClient.path == "api/v1/agent/stream")
    }
}
