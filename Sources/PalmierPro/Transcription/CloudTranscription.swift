import AVFoundation
import Foundation

/// 云端转写在 METAG 版本里不存在：音频不出用户设备是产品前提，不是可选项。
/// 保留这个类型只为让调用点继续编译；它一律改走 `Transcription`（Apple SpeechAnalyzer，端侧）。
enum CloudTranscription {
    static func transcribe(
        fileURL: URL,
        range: ClosedRange<Double>?,
        preferredLocale: Locale?,
        projectId: String?
    ) async throws -> TranscriptionResult {
        _ = projectId
        return try await Transcription.transcribe(
            fileURL: fileURL,
            preferredLocale: preferredLocale,
            sourceRange: range
        )
    }

    static func languageIdentifier(_ locale: Locale?) -> String? {
        locale?.language.languageCode?.identifier
    }
}
