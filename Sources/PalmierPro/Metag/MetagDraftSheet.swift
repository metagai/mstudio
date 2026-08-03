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
    /// 当前旁白人格。网关认不出的值一律当没有 —— 宁可不显示，也不显示一个错的。
    var narrator: MetagNarrator? { job?.narrator.flatMap(MetagNarrator.init(rawValue:)) }
    var ready: Bool { job?.status == "done" && !(job?.shots.isEmpty ?? true) }
    /// 已经取回的首帧，按镜号。**等待期间就开始填** ——
    /// 首帧比成片早得多，没有理由让用户对着转圈干等。
    @Published private(set) var frames: [Int: NSImage] = [:]

    private func fetchFrames(_ id: String, _ job: MetagGateway.Job) async {
        guard let names = job.first_frames else { return }
        for (i, name) in names.enumerated() where frames[i] == nil {
            guard let url = try? await MetagGateway.download(
                job: id, name: name, to: FileManager.default.temporaryDirectory),
                  let img = NSImage(contentsOf: url) else { continue }
            frames[i] = img
        }
    }

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

    /// 换旁白音色：整片重合成声音，**画面一帧不动，仍然 0 credits**。
    /// 比逐镜重做快得多（只跑 TTS，不占 GPU），所以用户可以随便试。
    func swapNarrator(_ n: MetagNarrator) async {
        guard let id = jobId, !busy, n != narrator else { return }
        busy = true; note = nil
        defer { busy = false }
        do {
            try await MetagGateway.revisePreview(id: id, narrator: n)
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
                await fetchFrames(id, j)
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

    /// 有没有档位坏到不能出片。
    ///
    /// 两种都要拦：选中的上限档停售了，**或者 local 停售了** ——
    /// 没有口播的镜头一律回落到 local，所以 local 一坏任何组合都出不了片。
    /// 不拦的话用户点下去拿一个 503，而他刚看完草案、正准备付钱。
    private var blocked: String? {
        func down(_ id: String) -> Bool { engines.first { $0.id == id }?.isAvailable == false }
        if down("local") { return "出片暂时不可用，稍后再试 —— 不会扣任何 credits" }
        if down(engine) { return "这一档暂时不可用，换一档" }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("先看草案，再决定出片").font(.headline)
            if model.jobId == nil {
                promptStage
            } else if model.ready {
                draftStage
            } else {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        ProgressView().controlSize(.small)
                        Text(model.frames.isEmpty
                             ? "正在起草…约 40 秒，不扣 credits"
                             : "画面陆续出来了，还在写旁白…")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    // 首帧一到就摆出来。等待不该是空白 —— 用户此刻最想看的
                    // 恰恰是"我的片子长什么样"，而这个答案已经有一半了。
                    if !model.frames.isEmpty {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            ForEach(model.frames.keys.sorted(), id: \.self) { i in
                                if let img = model.frames[i] {
                                    Image(nsImage: img)
                                        .resizable().aspectRatio(contentMode: .fill)
                                        .frame(width: 84, height: 48)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                        }
                    }
                }
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
            // 音色摆在引擎上面：用户先关心"谁在讲我的片子"，再关心画质档位。
            // 免费必须写出来，否则他不敢点 —— 而"敢试"正是这个交互的全部价值。
            if let current = model.narrator {
                Picker("旁白音色", selection: Binding(
                    get: { current },
                    set: { n in Task { await model.swapNarrator(n) } }
                )) {
                    ForEach(MetagNarrator.allCases, id: \.self) { n in
                        Text(n.displayName(for: "zh")).tag(n)
                    }
                }
                .font(.caption)
                .disabled(model.busy)
                Text("换音色免费，只重录声音，画面不变")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Picker("引擎", selection: $engine) {
                ForEach(engines, id: \.id) { e in
                    // 停售的档位标出来但**不隐藏** —— 抹掉会让用户以为
                    // "我昨天用的那档去哪了"，而让他选中再拿 503 更糟。
                    Text(e.isAvailable
                         ? "\(e.displayName(for: "zh")) · \(e.credits_per_shot)cr"
                         : "\(e.displayName(for: "zh")) · 暂不可用")
                        .tag(e.id)
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
                .disabled(model.busy || blocked != nil)
            }
            if let blocked {
                // 说出原因，而不是给一个禁用的按钮让用户猜
                Text(blocked).font(.caption2).foregroundStyle(.orange)
            }
        }
    }
}
