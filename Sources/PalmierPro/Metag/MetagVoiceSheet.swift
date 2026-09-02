import AppKit
import SwiftUI

/// 声音复刻：**用你自己的声音配音。**
///
/// ## 为什么复刻和配音要在同一个面板里
///
/// 网关的 `preview_revise` 只认固定的人格名（cinematic_male 之类），认不出的
/// 一律 400 —— 也就是说**复刻出来的音色用不到片子的旁白上**，它只能走
/// `/api/v1/tts` 独立配音。只做一个"我的音色"管理面板，等于交给用户一个
/// 他哪里都用不了的东西。所以这两件事必须一起给。
///
/// ## 授权那个勾
///
/// 音色属人身权。网关要求 consent 为 true，否则 403，并会记下来源 IP。
/// **这个勾不预勾选，也不能由「继续」隐含** —— 它是一次授权，不是一个偏好。
@MainActor
final class MetagVoiceModel: ObservableObject {
    @Published private(set) var voices: [MetagGateway.Voice] = []
    @Published private(set) var busy = false
    @Published var error: String?
    @Published var notice: String?
    /// 复刻单价。取自网关的 /pricing，**不写死** —— 写死的数字迟早和账单对不上。
    @Published private(set) var cloneCost: Int?

    func load() async {
        do {
            voices = try await MetagGateway.voices()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        cloneCost = try? await MetagGateway.pricing().extras?["voice_clone"]
    }

    func clone(sample: URL, name: String) async {
        busy = true
        defer { busy = false }
        do {
            let url = try await MetagGateway.uploadVoiceSample(sample)
            let created = try await MetagGateway.cloneVoice(sampleURL: url, name: name)
            // 宣称扣了多少一律用服务端回的 cost：复刻失败不扣费，只有成功那次才有这个数。
            // 拿本地单价重算，迟早会在某次调价后对用户说谎。
            notice = created.cost.map {
                L10n.string("Voice “\(name)” is ready — \($0.formatted()) credits")
            } ?? L10n.string("Voice “\(name)” is ready")
            error = nil
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ voice: MetagGateway.Voice) async {
        busy = true
        defer { busy = false }
        do {
            try await MetagGateway.deleteVoice(voice.id)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 合成一段配音并放进素材面板。
    ///
    /// **不自动落到时间线。** 配音要放在哪一句话上，只有用户知道；
    /// 替他决定一个位置，他多半还要再挪一次。
    func speak(text: String, voiceId: String?, editor: EditorViewModel) async {
        busy = true
        defer { busy = false }
        do {
            let url = try await MetagGateway.speak(
                text: text, voiceId: voiceId, to: FileManager.default.temporaryDirectory)
            editor.addMediaAsset(from: url, type: .audio)
            notice = L10n.key("Voiceover added to your media")
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// 复刻表单的三个条件。**从视图里搬出来，是为了能测。**
///
/// consent 默认 false 且没有任何代码路径把它置 true —— 它是一次授权，
/// 不是一个偏好，不许预勾选、也不许由「继续」隐含。
struct VoiceCloneForm: Equatable {
    var sample: URL?
    var name: String = ""
    var consent: Bool = false

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 能不能点"复刻"。三个条件缺一不可，网关那边还会再校验一次 consent。
    var isReady: Bool { sample != nil && consent && !trimmedName.isEmpty }

    /// 复刻成功后清空。**consent 也要清** —— 上一次的授权不适用于下一段样本。
    mutating func reset() { self = VoiceCloneForm() }
}

struct MetagVoiceSheet: View {
    @Environment(EditorViewModel.self) private var editor
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = MetagVoiceModel()

    @State private var form = VoiceCloneForm()
    @State private var script = ""
    @State private var speaking: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text(L10n.string("Your voices"))
                .font(.system(size: AppTheme.FontSize.lg, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(AppTheme.Text.primaryColor)

            voiceList
            Divider()
            cloneForm
            Divider()
            dubbing

            if let e = model.error {
                Text(e)
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Status.errorColor)
            } else if let n = model.notice {
                Text(n)
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
            }

            HStack {
                Spacer()
                Button(L10n.string("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(width: AppTheme.Director.sheetWidth)
        .task { await model.load() }
    }

    private var voiceList: some View {
        Group {
            if model.voices.isEmpty {
                Text(L10n.string("No cloned voices yet."))
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            } else {
                ForEach(model.voices) { v in
                    HStack {
                        Text(v.name)
                            .font(.system(size: AppTheme.FontSize.smMd))
                            .foregroundStyle(AppTheme.Text.primaryColor)
                        Spacer()
                        Button(L10n.string("Delete")) {
                            Task { await model.delete(v) }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: AppTheme.FontSize.xs))
                        .foregroundStyle(AppTheme.Status.errorColor)
                        .disabled(model.busy)
                    }
                }
            }
        }
    }

    private var cloneForm: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            Text(L10n.string("Clone a voice"))
                .font(.system(size: AppTheme.FontSize.smMd, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(AppTheme.Text.primaryColor)

            HStack(spacing: AppTheme.Spacing.smMd) {
                Button(L10n.string("Choose sample…")) { pickSample() }
                Text(form.sample?.lastPathComponent ?? L10n.key("WAV, MP3 or M4A · up to 16 MB"))
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                    .lineLimit(1)
            }

            TextField(L10n.string("Name this voice"), text: $form.name)

            // 授权：不预勾选。措辞说清楚"本人或已获授权"，因为这正是网关记录 IP 要留痕的那件事。
            Toggle(isOn: $form.consent) {
                Text(L10n.string("This sample is my own voice, or I have permission to use it."))
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
            }

            HStack {
                Button(cloneLabel) {
                    guard let sample = form.sample else { return }
                    let n = form.trimmedName
                    Task {
                        await model.clone(sample: sample, name: n)
                        if model.error == nil { form.reset() }
                    }
                }
                .disabled(!form.isReady || model.busy)
                if model.busy { ProgressView().controlSize(.small) }
            }
        }
    }

    /// 价钱取不到就**不提数字**。宁可少说一句，也不要说错一个数。
    private var cloneLabel: String {
        model.cloneCost.map { L10n.string("Clone · \($0.formatted()) credits") } ?? L10n.key("Clone")
    }

    private var dubbing: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            Text(L10n.string("Record a voiceover"))
                .font(.system(size: AppTheme.FontSize.smMd, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(AppTheme.Text.primaryColor)

            TextField(L10n.string("What should it say?"), text: $script, axis: .vertical)
                .lineLimit(2...5)

            HStack(spacing: AppTheme.Spacing.smMd) {
                Picker(L10n.string("Voice"), selection: $speaking) {
                    Text(L10n.string("Built-in (free)")).tag(String?.none)
                    ForEach(model.voices) { v in
                        Text(v.name).tag(String?.some(v.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: AppTheme.Director.sheetWidth / 2)

                Button(L10n.string("Generate")) {
                    let t = script.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task { await model.speak(text: t, voiceId: speaking, editor: editor) }
                }
                .disabled(model.busy || script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Text(L10n.string("Generated audio lands in your media panel — drag it onto the timeline."))
                .font(.system(size: AppTheme.FontSize.xxs))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
        }
    }

    private func pickSample() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.wav, .mp3, .mpeg4Audio]
        panel.message = L10n.key("Pick a clear 10–30 second sample of the voice.")
        guard panel.runModal() == .OK else { return }
        form.sample = panel.url
    }
}
