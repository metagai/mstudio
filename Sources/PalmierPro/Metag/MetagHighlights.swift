import SwiftUI

/// 找亮点：**素材不出设备，只有一份文字摘要出去。**
///
/// 转写在本机做（端侧 ASR），能量曲线也在本机算（AudioEnvelope），发给网关的
/// 只有转写文本和一条抽稀过的能量曲线 —— 这是我们能做而云端剪辑工具做不到的事，
/// 别为了省事把音视频传上去。
///
/// 选中的片段用现成的 `addClips(segments:)` 落到时间线，不另造一套裁切逻辑。
@MainActor
final class MetagHighlightsModel: ObservableObject {
    enum Stage: Equatable {
        case idle, transcribing, analyzing, asking, done
    }

    @Published private(set) var stage: Stage = .idle
    @Published private(set) var highlights: [MetagGateway.Highlight] = []
    @Published var preferences = ""
    @Published var error: String?

    var busy: Bool { stage != .idle && stage != .done }

    var stageLabel: String {
        switch stage {
        case .transcribing: L10n.key("Transcribing on this Mac…")
        case .analyzing: L10n.key("Measuring the audio…")
        case .asking: L10n.key("Looking for the good parts…")
        case .idle, .done: ""
        }
    }

    func find(url: URL) async {
        error = nil
        do {
            stage = .transcribing
            let result = try await Transcription.transcribeVideoAudio(videoURL: url)
            try Task.checkCancellation()

            stage = .analyzing
            let envelope = try await AudioEnvelopeExtractor.extract(from: url)
            try Task.checkCancellation()

            stage = .asking
            highlights = try await MetagGateway.highlights(
                transcript: result.text,
                energy: envelope.samples,
                duration: envelope.duration,
                preferences: preferences.trimmingCharacters(in: .whitespacesAndNewlines))
            stage = .done
        } catch is CancellationError {
            stage = .idle
        } catch {
            self.error = error.localizedDescription
            stage = .idle
        }
    }
}

struct MetagHighlightsSheet: View {
    let asset: MediaAsset

    @Environment(EditorViewModel.self) private var editor
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = MetagHighlightsModel()

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text(L10n.key("Find the good parts"))
                .font(.system(size: AppTheme.FontSize.lg, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(AppTheme.Text.primaryColor)

            // 说清楚什么出设备什么不出。这不是免责声明，是我们的卖点。
            Text(L10n.key("Transcription and audio analysis run on this Mac. Only the text leaves."))
                .font(.system(size: AppTheme.FontSize.xxs))
                .foregroundStyle(AppTheme.Text.tertiaryColor)

            TextField(L10n.key("Anything specific? e.g. 3 clips, 10 seconds each"),
                      text: $model.preferences)
                .disabled(model.busy)

            if model.busy {
                HStack(spacing: AppTheme.Spacing.sm) {
                    ProgressView().controlSize(.small)
                    Text(model.stageLabel)
                        .font(.system(size: AppTheme.FontSize.xs))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                }
            } else if let e = model.error {
                Text(e)
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Status.errorColor)
            } else if model.stage == .done && model.highlights.isEmpty {
                // 没找到也要说出来。空面板会被当成"还在转"。
                Text(L10n.key("Nothing stood out in this one."))
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }

            if !model.highlights.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
                        ForEach(model.highlights) { row($0) }
                    }
                }
                .frame(maxHeight: AppTheme.Onboarding.cardHeight / 2)
            }

            HStack {
                Spacer()
                Button(L10n.key("Close")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(model.stage == .done ? L10n.key("Search again") : L10n.key("Find highlights")) {
                    Task { await model.find(url: asset.url) }
                }
                .disabled(model.busy)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(width: AppTheme.Director.sheetWidth)
    }

    private func row(_ h: MetagGateway.Highlight) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.smMd) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text("\(timecode(h.start)) – \(timecode(h.end))  \(h.title)")
                    .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Text(h.reason)
                    .font(.system(size: AppTheme.FontSize.xxs))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: AppTheme.Spacing.xs)
            Button(L10n.key("Add")) { add(h) }
        }
    }

    /// 把这一段接到时间线末尾。用现成的 addClips(segments:)，
    /// **不另造一套裁切**：一处算错的裁切迟早和别处对不上。
    private func add(_ h: MetagGateway.Highlight) {
        guard h.end > h.start else { return }
        let track = editor.timeline.tracks.firstIndex { $0.type == .video } ?? 0
        let end = editor.timeline.tracks.indices.contains(track)
            ? (editor.timeline.tracks[track].clips.map { $0.startFrame + $0.durationFrames }.max() ?? 0)
            : 0
        editor.addClips(
            assets: [asset], trackIndex: track, startFrame: end,
            segments: [asset.id: h.start...h.end])
    }

    private func timecode(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// 待找亮点的素材。走 `.sheet(item:)`，理由同 ImageEditRequest。
struct HighlightRequest: Identifiable, Equatable {
    let assetId: String
    var id: String { assetId }
}
