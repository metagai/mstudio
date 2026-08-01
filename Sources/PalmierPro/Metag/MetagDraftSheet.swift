import SwiftUI

/// 免费草案：先看片，再决定付不付钱。
///
/// web 端一直有这条路，macOS 端此前没有 —— 用户从生成对话框直接走付费出片。
/// 而"先看后买"正是首页对外的承诺，两端不一致等于对一半用户失约。
///
/// 三段式，与 web 端同一套语义：
///   起草（0 credits）→ 逐镜改（仍 0 credits，只重做被改的那几镜）→ 确认出片（此刻才计费）
@MainActor
final class MetagDraftModel: ObservableObject {
    @Published var prompt = ""
    @Published var shots = 4
    @Published private(set) var jobId: String?
    @Published private(set) var job: MetagGateway.Job?
    @Published private(set) var busy = false
    @Published private(set) var note: String?
    /// 逐镜改过的旁白。key 是镜号 —— 只有真变了的才发出去。
    @Published var edits: [Int: String] = [:]
    @Published var rerolls: Set<Int> = []

    var narrations: [String] { job?.shots.map(\.narration) ?? [] }
    var ready: Bool { job?.status == "done" && !(job?.shots.isEmpty ?? true) }

    /// 真正会改变草案的编辑条数。不能直接数 `edits` 的键 ——
    /// 用户打了个字又删回去，键还在，于是"重做 1 镜"会拿着一模一样的旁白再合成一遍。
    var effectiveEdits: [MetagGateway.ReviseEdit] {
        var out: [MetagGateway.ReviseEdit] = []
        for (i, text) in edits where i < narrations.count && text != narrations[i] && !text.isEmpty {
            out.append(.init(index: i, narration: text, reroll: rerolls.contains(i) ? true : nil))
        }
        for i in rerolls where edits[i] == nil {
            out.append(.init(index: i, narration: nil, reroll: true))
        }
        return out
    }

    func draft() async {
        guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty, !busy else { return }
        busy = true; note = nil
        defer { busy = false }
        do {
            let id = try await MetagGateway.preview(prompt: prompt, shots: shots)
            jobId = id
            await poll(id)
        } catch {
            note = error.localizedDescription
        }
    }

    func revise() async {
        guard let id = jobId, !effectiveEdits.isEmpty, !busy else { return }
        busy = true; note = nil
        defer { busy = false }
        do {
            try await MetagGateway.revisePreview(id: id, edits: effectiveEdits)
            edits.removeAll(); rerolls.removeAll()
            await poll(id)
        } catch {
            note = error.localizedDescription
        }
    }

    /// 确认出片。**此刻才计费** —— 返回成片任务 id 交给调用方去等。
    func approve(engine: String, allShots: Bool) async -> String? {
        guard let id = jobId, !busy else { return nil }
        busy = true; note = nil
        defer { busy = false }
        do {
            return try await MetagGateway.approvePreview(id: id, engine: engine, allShots: allShots)
        } catch {
            note = error.localizedDescription
            return nil
        }
    }

    private func poll(_ id: String) async {
        for _ in 0..<90 {
            if let j = try? await MetagGateway.job(id) {
                job = j
                if j.status == "done" || j.status == "failed" { return }
            }
            try? await Task.sleep(for: .seconds(4))
        }
        note = L10n.key("The draft is taking too long — try again in a moment.")
    }
}

struct MetagDraftSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(EditorViewModel.self) private var editor
    @StateObject private var model = MetagDraftModel()
    @State private var engines: [MetagGateway.Pricing.Engine] = []
    @State private var engine = "local"
    /// 全片使用所选引擎。**默认关** —— 默认只有口播镜用贵引擎，其余降到 local。
    @State private var allShots = false

    private var perShot: Int { engines.first { $0.id == engine }?.credits_per_shot ?? 1 }
    /// 报价必须等于实扣：默认路由下只有口播镜走贵引擎，这里没有逐镜口播标记，
    /// 所以只在"全片使用"时按贵引擎报价，否则按 local 报 —— 宁可少报也不能多报。
    private var quote: Int { allShots ? perShot * model.shots : model.shots }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("先看草案，再决定出片").font(.headline)
            if model.jobId == nil {
                promptStage
            } else if model.ready {
                draftStage
            } else {
                ProgressView().controlSize(.small)
                Text("正在起草…约 40 秒，不扣 credits")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let n = model.note {
                Text(n).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(width: 460)
        .task {
            engines = (try? await MetagGateway.pricing().engines) ?? []
        }
    }

    private var promptStage: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            TextField("一句话说清楚要拍什么", text: $model.prompt, axis: .vertical)
                .lineLimit(2...4)
            Stepper("\(model.shots) 个镜头", value: $model.shots, in: 1...8)
                .font(.caption)
            // 把代价说在前面：草案免费。不说清楚的话，用户不敢点。
            Text("草案免费，不扣任何 credits").font(.caption).foregroundStyle(.green)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("起草") { Task { await model.draft() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy || model.prompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var draftStage: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            ForEach(Array(model.narrations.enumerated()), id: \.offset) { i, text in
                VStack(alignment: .leading, spacing: 2) {
                    TextField("第 \(i + 1) 镜旁白", text: Binding(
                        get: { model.edits[i] ?? text },
                        set: { model.edits[i] = $0 }
                    ))
                    .font(.caption)
                    Toggle("换个画面", isOn: Binding(
                        get: { model.rerolls.contains(i) },
                        set: { on in if on { model.rerolls.insert(i) } else { model.rerolls.remove(i) } }
                    ))
                    .toggleStyle(.checkbox).font(.caption2)
                }
            }
            Divider()
            Picker("引擎", selection: $engine) {
                ForEach(engines, id: \.id) { e in
                    Text("\(e.displayName(for: "zh")) · \(e.credits_per_shot)cr").tag(e.id)
                }
            }
            .font(.caption)
            if engine != "local" {
                Toggle("全片都用这一档", isOn: $allShots).font(.caption2)
                if !allShots {
                    // 说清楚默认会发生什么，而不是让他看完成片再问"为什么画质没变"
                    Text("默认只有需要对口型的镜头用它，其余走标准档")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("重做改过的镜头") { Task { await model.revise() } }
                    .disabled(model.busy || model.effectiveEdits.isEmpty)
                Spacer()
                Text("确认后扣 \(quote) credits").font(.caption).foregroundStyle(.secondary)
                Button("确认出片") {
                    Task {
                        if let job = await model.approve(engine: engine, allShots: allShots) {
                            editor.mediaPanelToast = MediaPanelToast(
                                message: L10n.key("Generating — shots will land as they finish."),
                                kind: .progress)
                            await MetagJobOpener.open(jobId: job, into: editor)
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.busy)
            }
        }
    }
}
