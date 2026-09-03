import Testing
@testable import PalmierPro

/// **按下去、等完、一个字都没有** —— 和「把不知道画成事实」是一对：
/// 那一族说了假话，这一族什么都不说。两者他都得自己猜。
@Suite("什么都没发生的时候屏幕上写什么")
struct SilentNothingTests {
    /// 三种"什么都没有"，他要做的事完全不同。
    @Test func identifyNamesWhichKindOfNothing() {
        let none = EditorViewModel.nothingToIdentify(audioClips: 0, onTimeline: 0)
        let offTimeline = EditorViewModel.nothingToIdentify(audioClips: 3, onTimeline: 0)
        let noSpeech = EditorViewModel.nothingToIdentify(audioClips: 3, onTimeline: 2)
        for m in [none, offTimeline, noSpeech] {
            #expect(!m.isEmpty, "一次认不出人的 Identify 什么都没说")
        }
        #expect(Set([none, offTimeline, noSpeech]).count == 3,
                "三种情况说了同一句 —— 等于把问题原样退还给他")
    }

    /// **不按信封回的 body，恰恰是最不能给人看的东西。**
    ///
    /// 上一版把 `body.prefix(500)` 直接放进聊天框：nginx 的 502 页面、
    /// 网关的堆栈、截断到一半的 JSON。判据量的是**屏幕上那句话里有没有源码**，
    /// 不是源码里那个 `prefix(500)` 还在不在。
    @Test(arguments: [
        (502, "<html>\r\n<head><title>502 Bad Gateway</title></head>\r\n<body><center><h1>502</h1></center><hr><center>nginx/1.24.0</center></body>\r\n</html>"),
        (500, "Traceback (most recent call last):\n  File \"/app/main.py\", line 88, in generate\n    raise RuntimeError(\"pool exhausted\")"),
        (503, "{\"error\":{\"cod"),
        (429, ""),
    ])
    func aBrokenBodyNeverReachesTheScreen(status: Int, body: String) {
        let shown = AgentServiceError.from(status: status, body: body).errorDescription ?? ""
        #expect(!shown.isEmpty, "HTTP \(status) 之后聊天框里一个字都没有")
        for leak in ["<html", "<head", "nginx", "Traceback", "File \"", "{\"error"] {
            #expect(!shown.contains(leak),
                    "HTTP \(status) 把源码送到了屏幕上：\(shown.prefix(80))")
        }
    }

    /// 网关**按约定**回了信封时，那句话要照原样用 —— 它才是最准的。
    @Test func aProperEnvelopeStillSpeaksForItself() {
        let body = #"{"error":{"code":"insufficient_credits","message":"You need 180 more credits."}}"#
        let error = AgentServiceError.from(status: 402, body: body)
        guard case .insufficientCredits(let m) = error else {
            Issue.record("按约定回的 402 没被认出来")
            return
        }
        #expect(m == "You need 180 more credits.")
    }
}
