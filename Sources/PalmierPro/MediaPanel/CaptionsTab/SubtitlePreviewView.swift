import SwiftUI

struct SubtitlePreviewView: View {
    let url: URL?

    @State private var cues: [SubtitleCue] = []
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage {
                unavailable(message: errorMessage)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.mdLg) {
                        ForEach(Array(cues.enumerated()), id: \.offset) { index, cue in
                            cueRow(index: index + 1, cue: cue)
                        }
                    }
                    .padding(AppTheme.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Background.previewCanvasColor)
        .task(id: url) {
            guard let url else {
                cues = []
                errorMessage = L10n.string("Subtitle file is unavailable.")
                return
            }
            do {
                let parsed = try await SubtitleFileParser.parseFile(at: url)
                guard !Task.isCancelled else { return }
                cues = parsed
                errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                cues = []
                // **界面上说人话，机器契约留给机器。**
                // `errorDescription` 是 `add_captions` 那个 MCP 工具的错误串，
                // 不许本地化；这里用它的 `userMessage`。
                errorMessage = (error as? SubtitleFileParser.ParseError)?.userMessage
                    ?? error.localizedDescription
            }
        }
    }

    private func cueRow(index: Int, cue: SubtitleCue) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Text(verbatim: "\(index)")
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                Text(verbatim: "\(timestamp(cue.startSeconds)) --> \(timestamp(cue.endSeconds))")
                    .foregroundStyle(AppTheme.Accent.timecodeColor)
            }
            .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.medium).monospaced())
            Text(verbatim: cue.text)
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.primaryColor)
                .textSelection(.enabled)
        }
    }

    private func unavailable(message: String) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "captions.bubble")
                .font(.system(size: AppTheme.IconSize.lg))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
            Text(message)
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .multilineTextAlignment(.center)
        }
        .padding(AppTheme.Spacing.lg)
    }

    private func timestamp(_ seconds: Double) -> String {
        let millis = Int((seconds * 1000).rounded())
        return String(
            format: "%02d:%02d:%02d,%03d",
            millis / 3_600_000, millis / 60_000 % 60, millis / 1000 % 60, millis % 1000
        )
    }
}
