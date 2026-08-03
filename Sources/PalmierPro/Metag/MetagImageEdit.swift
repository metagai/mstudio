import SwiftUI

/// 一句话改图：**改完先看见，再决定用不用。**
///
/// web 端至今是盲改 —— `/api/v1/image/edit` 只回一个 frame_id，而那张图没有任何
/// 路由能读回来，用户花 4 credits 改完只能等生成之后才知道改成了什么样。
/// 为此在网关补了 `GET /api/v1/frames/{id}`，两端都受益。
///
/// 结果作为**一张新素材**落进素材面板，原图不动：改图是加一版，不是替换。
/// 一次没改对，原图还在。
@MainActor
final class MetagImageEditModel: ObservableObject {
    @Published var instruction = ""
    @Published private(set) var busy = false
    @Published var error: String?
    /// 改出来的那张，先给用户看。用不用是下一步的事。
    @Published private(set) var preview: (url: URL, cost: Int)?
    @Published private(set) var cost: Int?

    func loadCost() async {
        cost = try? await MetagGateway.pricing().extras?["image_edit"]
    }

    func run(source: URL) async {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            let frameId = try await MetagGateway.uploadFrame(source)
            let edited = try await MetagGateway.editImage(frameId: frameId, instruction: text)
            let local = try await MetagGateway.frame(
                edited.frameId, to: FileManager.default.temporaryDirectory)
            // 实扣金额用服务端回的 cost，不拿本地单价重算 —— 失败不扣费，
            // 只有成功那次才有这个数。
            preview = (local, edited.cost)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct MetagImageEditSheet: View {
    let source: URL

    @Environment(EditorViewModel.self) private var editor
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = MetagImageEditModel()

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text(L10n.key("Edit with a sentence"))
                .font(.system(size: AppTheme.FontSize.lg, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(AppTheme.Text.primaryColor)

            HStack(alignment: .top, spacing: AppTheme.Spacing.smMd) {
                imageBox(url: source, caption: L10n.key("Original"))
                if let p = model.preview {
                    imageBox(url: p.url, caption: L10n.string("Edited · \(p.cost.formatted()) credits"))
                }
            }

            TextField(L10n.key("What should change? e.g. make it night, add rain"),
                      text: $model.instruction, axis: .vertical)
                .lineLimit(1...3)
                .disabled(model.busy)

            if let e = model.error {
                Text(e)
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Status.errorColor)
            }

            HStack(spacing: AppTheme.Spacing.smMd) {
                if model.busy { ProgressView().controlSize(.small) }
                Spacer()
                Button(L10n.key("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                if let p = model.preview {
                    Button(L10n.key("Add to media")) {
                        editor.addMediaAsset(from: p.url, type: .image)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
                Button(runLabel) { Task { await model.run(source: source) } }
                    .disabled(model.busy
                        || model.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(width: AppTheme.Director.sheetWidth)
        .task { await model.loadCost() }
    }

    /// 价钱取不到就**不提数字**。宁可少说一句，也不要说错一个数。
    /// 两个分支各写各的键。**不要把 base 插值进 L() 的参数** ——
    /// 我们的 L() 以英文原串为键，动态拼出来的键翻译表里找不到，
    /// 而且漏了也不会报错，只会在界面上显示成英文。
    private var runLabel: String {
        if let c = model.cost {
            return model.preview == nil
                ? L10n.string("Edit · \(c.formatted()) credits")
                : L10n.string("Edit again · \(c.formatted()) credits")
        }
        return model.preview == nil ? L10n.key("Edit") : L10n.key("Edit again")
    }

    private func imageBox(url: URL, caption: String) -> some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fit) } placeholder: {
                AppTheme.Background.surfaceColor
            }
            .frame(height: AppTheme.Onboarding.welcomeHeroHeight / 2)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
            Text(caption)
                .font(.system(size: AppTheme.FontSize.xxs))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 待改的那张图。走 `.sheet(item:)` 而不是 `isPresented`：
/// 后者会让"改哪张"和"面板开着没有"变成两份互不相干的状态。
struct ImageEditRequest: Identifiable, Equatable {
    let source: URL
    var id: String { source.path }
}
