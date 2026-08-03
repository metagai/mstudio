import AVFoundation
import SwiftUI

/// 多版本择优：**用户为几个候选付了钱，挑选权就该在他手里。**
///
/// 「Three More Takes」一直是生成 3 条、然后自动采用最后一条 —— 另外两条留在
/// 服务器上，用户既看不到也换不了。候选数据其实一直躺在 job.alts 里。
///
/// ## 为什么要下载再看
///
/// 光按分数挑不算挑。那个分数是技术质量门给的（冻帧、噪点、纯色），它回答
/// "这条能不能用"，回答不了"这条是不是我要的"。所以要出画面。
@MainActor
final class MetagTakePickerModel: ObservableObject {
    struct Candidate: Identifiable {
        let file: String
        let score: Double
        var localURL: URL?
        var thumbnail: CGImage?
        var id: String { file }
    }

    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var loading = true
    @Published var error: String?

    func load(job: String, shot: Int) async {
        loading = true
        defer { loading = false }
        do {
            let detail = try await MetagGateway.job(job)
            let takes = detail.alts?.indices.contains(shot) == true ? detail.alts?[shot] ?? [] : []
            candidates = takes.map { Candidate(file: $0.file, score: $0.score) }
            // 逐条下载出图。**串行**：候选一般 2–4 条，几 MB，
            // 并发下载省不下多少，却会和正在跑的出片抢同一条跨太平洋的链路。
            for i in candidates.indices {
                guard let url = try? await MetagGateway.download(
                    job: job, name: candidates[i].file, to: FileManager.default.temporaryDirectory)
                else { continue }
                candidates[i].localURL = url
                candidates[i].thumbnail = await VideoThumbnail.image(url: url, at: 0.5)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct MetagTakePicker: View {
    let job: String
    let shot: Int
    let assetId: String

    @Environment(EditorViewModel.self) private var editor
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = MetagTakePickerModel()
    @State private var promoting: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text(L10n.key("Pick a take"))
                .font(.system(size: AppTheme.FontSize.lg, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(AppTheme.Text.primaryColor)

            if model.loading {
                HStack(spacing: AppTheme.Spacing.sm) {
                    ProgressView().controlSize(.small)
                    Text(L10n.key("Fetching takes…"))
                        .font(.system(size: AppTheme.FontSize.xs))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                }
            } else if let e = model.error {
                Text(e)
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Status.errorColor)
            } else if model.candidates.count < 2 {
                // 只有一条时说清楚为什么没得挑，不要给一个空面板。
                Text(L10n.key("This shot has only one take. Re-shoot with more takes to compare."))
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            } else {
                HStack(alignment: .top, spacing: AppTheme.Spacing.smMd) {
                    ForEach(model.candidates) { c in takeCard(c) }
                }
            }

            HStack {
                Spacer()
                Button(L10n.key("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(width: AppTheme.Director.sheetWidth)
        .task { await model.load(job: job, shot: shot) }
    }

    private func takeCard(_ c: MetagTakePickerModel.Candidate) -> some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            Group {
                if let img = c.thumbnail {
                    Image(decorative: img, scale: 1)
                        .resizable().aspectRatio(contentMode: .fill)
                } else {
                    AppTheme.Background.surfaceColor
                }
            }
            .frame(height: AppTheme.Onboarding.welcomeHeroHeight / 2)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))

            // 分数如实标成"技术质量"：它判的是能不能用，不是好不好看。
            Text(L10n.string("Quality \((c.score * 100).rounded().formatted())"))
                .font(.system(size: AppTheme.FontSize.xxs))
                .foregroundStyle(AppTheme.Text.tertiaryColor)

            Button(promoting == c.file ? L10n.key("Working…") : L10n.key("Use this")) {
                promoting = c.file
                Task { await use(c) }
            }
            .disabled(promoting != nil || c.localURL == nil)
        }
        .frame(maxWidth: .infinity)
    }

    private func use(_ c: MetagTakePickerModel.Candidate) async {
        guard let local = c.localURL else { return }
        do {
            // 先服务端定版，再换本地画面。反过来的话，服务端失败时用户已经看到新画面，
            // 而下次打开工程又变回旧的 —— 那种不一致最难解释。
            try await MetagGateway.promoteTake(job: job, shot: shot, file: c.file)
            let installed = try await editor.commitStagedProjectMedia(
                local, filename: local.lastPathComponent)
            guard let asset = editor.mediaAssets.first(where: { $0.id == assetId }) else {
                dismiss()
                return
            }
            let previousURL = asset.url
            editor.undo.perform(L10n.key("Pick a take")) {
                editor.registerTimelineUndo(L10n.key("Pick a take")) { vm in
                    vm.relinkAsset(id: assetId, to: previousURL)
                }
                editor.relinkAsset(id: assetId, to: installed)
            }
            dismiss()
        } catch {
            model.error = error.localizedDescription
            promoting = nil
        }
    }
}

/// 待挑选的那一镜。`Identifiable` 是为了走 `.sheet(item:)` ——
/// 用 `isPresented` 的话，面板打开后 job/shot 就成了两份互不相干的状态，
/// 换一个片段再打开会拿到上一次的参数。
struct TakePick: Identifiable, Equatable {
    let job: String
    let shot: Int
    let assetId: String
    var id: String { "\(job)#\(shot)" }
}
