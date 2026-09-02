import Foundation
import Testing
@testable import PalmierPro

/// **不许卖一个我们故意不做的东西。**
///
/// `CloudTranscription` 文件开头自己写着：
/// 「云端转写在 METAG 版本里不存在：**音频不出用户设备是产品前提，不是可选项**」，
/// 而它的实现原样调 `Transcription`（Apple SpeechAnalyzer，端侧）。
///
/// **实现是对的，说谎的是界面。** 字幕面板上那一档标着
/// 「自动识别语言、更准、能分辨说话人、25 credits/小时」，
/// 未登录灰掉、额度为 0 灰掉，`onReset` 还把用户推到这一档。
///
/// 三件事一起发生：**给不存在的功能标了价、为不花钱的功能设了两道门、
/// 而且把我们最强的那条承诺（音频不出你的机器）说成了一条收费劣势。**
@Suite("转写：不卖不存在的东西")
struct NoFakePaidTierTests {
    private func source(_ name: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PalmierPro/\(name)"), encoding: .utf8)
    }

    /// **"云端"这条实现确实是端侧的** —— 先证明这一点，
    /// 否则下面那条"界面不许提它"就可能是在删一个真功能。
    @Test func theCloudPathIsActuallyLocal() throws {
        let src = try source("Transcription/CloudTranscription.swift")
        #expect(src.contains("Transcription.transcribe("),
                "云端那条不再走端侧了 —— 那么下面那几条判据的前提就没了")
        #expect(!src.contains("URLSession"), "它真的开始联网了")
    }

    /// 界面上不许再有那个档、那个价、那两道门。
    @Test func theCaptionPanelNeitherChargesNorGates() throws {
        let src = try source("MediaPanel/CaptionsTab/CaptionTab.swift")
        for (needle, why) in [
            ("Sign in to use Cloud", "为一个不花钱的功能设了登录门"),
            ("Add credits to use Cloud", "为一个不花钱的功能设了额度门"),
            ("25 credits/hr", "给一个不存在的功能标了价"),
            ("provider = .cloud", "重置会把他推到那个不存在的档"),
        ] {
            #expect(!src.contains(needle), "\(why)（还留着「\(needle)」）")
        }
    }

    /// **而且要把那句话翻过来说。**
    ///
    /// 同一个事实：音频不出这台机器。上一版把它说成"你得付费才能用更好的"，
    /// 现在说成它本来的样子 —— 一条承诺。
    @Test func thePromiseIsStatedAsAPromise() throws {
        let src = try source("MediaPanel/CaptionsTab/CaptionTab.swift")
        #expect(src.contains("your audio never leaves it"),
                "删掉了那个假档，但没把那条承诺说出来 —— 那等于白删")
    }
}
