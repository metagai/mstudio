import SwiftUI

extension Notification.Name {
    /// 引导页那颗主按钮：**先看一眼你的片子**，不是先登录。
    /// 用通知而不是共享状态：发起的是首屏，接住的是媒体面板，两者互不认识。
    static let metagStartDraft = Notification.Name("metagStartDraft")
}

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
    /// 网关给的这一条片子的报价。为空就退回本地按档位单价算 ——
    /// 那是第二份真源，只在问不到价时用。
    @Published var quote: MetagGateway.Quote?
    @Published private(set) var jobId: String?
    @Published private(set) var job: MetagGateway.Job?
    @Published private(set) var busy = false
    @Published private(set) var note: String?
    /// 逐镜改过的旁白。key 是镜号 —— 只有真变了的才发出去。
    @Published var edits: [Int: String] = [:]
    @Published var rerolls: Set<Int> = []

    /// 等待时那一行字。**说正在做哪一步，而不是一个不动的"正在起草"。**
    ///
    /// 实测草案 53–97 秒，其中 planning 一段就占 26–36 秒 —— 那段时间里
    /// 我们依次在写分镜、挑音色、录旁白，只是从没说出来过。
    var stageText: String {
        switch job?.stage {
        case "storyboard": return L10n.key("Writing the shot list…")
        case "voice": return L10n.key("Choosing a narrator voice…")
        case "narration": return L10n.key("Recording the narration…")
        case "frames": return L10n.key("Painting the first frames…")
        case "music": return L10n.key("Scoring it…")
        default:
            // 阶段还没上来（刚提交、或老网关）。**不给数字** ——
            // 原来那句写着"约 40 秒"而实测是 53–97 秒，给错的数字比不给更糟。
            return frames.isEmpty
                ? L10n.key("Drafting… this one is free")
                : L10n.key("Frames are landing, still writing the narration…")
        }
    }

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
        // 这两步分开记。**「打了字」和「敢按下去」是两件事** ——
        // 合成一步就看不出"写完了却没按"这一段流失，而那一段最值钱。
        MetagFunnel.track(.lineReady)
        MetagFunnel.track(.draftStarted)
        busy = true; note = nil
        defer { busy = false }
        // 陌生人也能先看一眼。**他刚下完一个安装包，比网页访客更有耐心，
        // 但这不构成让他先交身份的理由。** 领不到票就退回原来的行为（让他登录），
        // 不把网络故障说成"请先登录"。
        guard await MetagGateway.ensureTicket() else {
            note = L10n.key("Couldn't reach METAG — check your connection and try again.")
            return
        }
        // 同时去问价。**报价免费也不需要登录**，而等草案的那 90 秒本来就是空的 ——
        // 让他在决定之前就知道代价，而不是按下去之后看余额少了多少。
        // 失败一律吞掉：问不到价不该挡住免费草案。
        Task { [prompt, shots] in
            let lang = AppLocalization.shared.selection.identifier.map { String($0.prefix(2)) } ?? "en"
            quote = try? await MetagGateway.quote(prompt: prompt, shots: shots, lang: lang)
        }
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
            let job = try await MetagGateway.approvePreview(id: id, engine: engine, allShots: allShots)
            // **网关收下了才算。** 记在按钮上的话，一次失败的批准会让转化率
            // 凭空变好而钱一分没进来 —— 而我们会照着那个数去排下一步的工。
            // 带上这一单的档位和报价：报价有没有改变他的选择，只能在这里看出来。
            MetagFunnel.track(.paid, once: false, meta: [
                "engine": engine,
                "credits": quote?.options.first { $0.engine == engine }?.total_credits ?? 0,
                "quoted": quote != nil,
            ])
            return job
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
                if j.status == "done" || j.status == "failed" {
                    // **草案真的到他屏幕上了** —— 判据落在"渲完并且这一页还在"，
                    // 不落在"我们提交成功了"。那两件事之间就是流失。
                    if j.status == "done" { MetagFunnel.track(.draftSeen) }
                    return
                }
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
    @State private var engine = MetagDraftSheet.fallbackEngineID
    // 免费试渲：一人一次，所以只有"没用过 / 正在渲 / 已经用过"三种
    @State private var sampling = false
    @State private var sampled = false
    @State private var sampleError: String?
    /// 界面语言，映射到网关的 zh/en/es。引擎名要跟着它走 —— 此前写死 "zh"，
    /// 英文和西语用户在**决定花多少钱的那一步**看到的是中文档位名。
    private var uiLang: String {
        switch AppLocalization.shared.selection.identifier?.prefix(2) {
        case "zh": "zh"
        case "es": "es"
        default: "en"
        }
    }
    /// 全片使用所选引擎。**默认关** —— 默认只有口播镜用贵引擎，其余降到 local。
    @State private var allShots = false

    /// 没有口播的镜头一律回落到这一档 —— **这是服务端的路由规则，不是客户端能算出来的**，
    /// 所以它是一个写明出处的常量，而不是一段假装在推导的代码。
    /// 客户端唯一能做的是：拿它去报价单里查这一档还在不在。
    private static let fallbackEngineID = "local"

    private var perShot: Int { engines.first { $0.id == engine }?.credits_per_shot ?? 1 }

    /// 免费试渲用哪一档。
    ///
    /// **原来写死 `"seedance"`**。写死的那天 seedance 确实是最便宜的付费档；
    /// 后来上了 wan-flash（7cr），seedance 涨到 34cr，而这一行没人改 ——
    /// 于是"看看付费档长什么样"给新用户看的是一档他用注册赠额买不起的模型。
    /// 现在取报价单里**最便宜的那一档付费档**：它既是新用户真买得起的，
    /// 也让他之后看到的报价对得上。
    private var sampleTier: MetagGateway.Pricing.Engine? {
        // 已经选了付费档就试他选的那一档 —— 他想看的是自己要买的东西。
        if engine != Self.fallbackEngineID,
           let picked = engines.first(where: { $0.id == engine }), picked.isAvailable {
            return picked
        }
        return engines
            .filter { $0.isAvailable && $0.id != Self.fallbackEngineID }
            .min { $0.credits_per_shot < $1.credits_per_shot }
    }

    /// 选中的档位自带台词/音效/环境声。取自报价单，不硬编引擎名单 ——
    /// 加一档模型时硬编的名单必然忘记更新，而忘记的后果是静默的。
    private var selectedEngineHasNativeAudio: Bool {
        engines.first { $0.id == engine }?.native_audio == true
    }
    /// 报价必须等于实扣：默认路由下只有口播镜走贵引擎，这里没有逐镜口播标记，
    /// 所以只在"全片使用"时按贵引擎报价，否则按 local 报 —— 宁可少报也不能多报。
    private var quote: Int {
        guard allShots else { return model.shots }
        // 网关的登记表是唯一真源。本地那份 `perShot × shots` 只在问不到价时兜底 ——
        // 网关改了档位价格，本地那份会照旧报旧价，而用户按下去扣的是新价。
        return model.quote?.options.first { $0.engine == engine }?.total_credits
            ?? perShot * model.shots
    }

    /// 有没有档位坏到不能出片。
    ///
    /// 两种都要拦：选中的上限档停售了，**或者 local 停售了** ——
    /// 没有口播的镜头一律回落到 local，所以 local 一坏任何组合都出不了片。
    /// 不拦的话用户点下去拿一个 503，而他刚看完草案、正准备付钱。
    /// 出片要花多少 —— 在他决定之前。
    ///
    /// 只说推荐档那一个数。**给六档价目表等于把选择的负担丢回给他**，
    /// 而他此刻连片子长什么样都还没看到。想比价的人到批准那一步有完整列表。
    @ViewBuilder
    private func quotePreview(_ rec: MetagGateway.Quote.Option, why: String?) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
            HStack(spacing: AppTheme.Spacing.xxs) {
                Image(systemName: "sparkles")
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Accent.brand)
                Text(L10n.string("Producing this will cost about \(rec.total_credits.formatted()) credits"))
                    .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.medium))
            }
            if let why {
                Text(verbatim: why)
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Text.mutedColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, AppTheme.Spacing.xxs)
    }

    private var blocked: String? {
        func down(_ id: String) -> Bool { engines.first { $0.id == id }?.isAvailable == false }
        if down(Self.fallbackEngineID) { return L10n.key("Generation is unavailable right now — try again later, nothing will be charged") }
        if down(engine) { return L10n.key("That engine is temporarily unavailable — pick another") }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text(L10n.key("See the draft first, then decide")).font(.headline)
            if model.jobId == nil {
                promptStage
            } else if model.ready {
                draftStage
            } else {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    // 说的是**谁在干什么**，而不是干到百分之几。
                    // 原来这里是一个转圈加一句"正在起草"；那句话曾经写着"约 40 秒"，
                    // 而实测 53–97 秒 —— 被告知 40 秒却等了 90 秒的人会觉得产品坏了。
                    // 现在不给数字，给的是这一刻真的有人在做的那件事。
                    MetagCrewView(
                        stage: model.job?.stage,
                        shotCount: model.job?.shots.count.nonZero ?? model.shots
                    )
                    // 等待期间就把代价说了。**这 90 秒本来是空的**，而他等完
                    // 之后要做的第一个决定就是"要不要花这笔钱" —— 让他在等的时候
                    // 就已经知道，而不是等完才第一次听到数字。
                    if let q = model.quote, let rec = q.recommended {
                        quotePreview(rec, why: q.why(uiLang))
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
            TextField(L10n.key("Say what you want to film, in one line"), text: $model.prompt, axis: .vertical)
                .lineLimit(2...4)
            Stepper(L10n.string("\(model.shots.formatted()) shots"), value: $model.shots, in: 1...8)
                .font(.caption)
            // 把代价说在前面：草案免费。不说清楚的话，用户不敢点。
            Text(L10n.key("Drafts are free — no credits charged")).font(.caption).foregroundStyle(.green)
            HStack {
                Spacer()
                Button(L10n.key("Cancel")) { dismiss() }
                Button(L10n.key("Draft it")) { Task { await model.draft() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy || model.prompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var draftStage: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            ForEach(Array(model.narrations.enumerated()), id: \.offset) { i, text in
                VStack(alignment: .leading, spacing: 2) {
                    TextField(L10n.string("Shot \((i + 1).formatted()) narration"), text: Binding(
                        get: { model.edits[i] ?? text },
                        set: { model.edits[i] = $0 }
                    ))
                    .font(.caption)
                    Toggle(L10n.key("Different composition"), isOn: Binding(
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
                Picker(L10n.key("Narrator voice"), selection: Binding(
                    get: { current },
                    set: { n in Task { await model.swapNarrator(n) } }
                )) {
                    ForEach(MetagNarrator.allCases, id: \.self) { n in
                        Text(n.displayName(for: "zh")).tag(n)
                    }
                }
                .font(.caption)
                .disabled(model.busy)
                Text(L10n.key("Changing the voice is free — only the narration is re-recorded"))
                    .font(.caption2).foregroundStyle(.secondary)
                // 选中的档位自带音轨时，这个音色只作用于草案。**说出来** ——
                // 否则用户挑了半天旁白，成片里说话的是模型自己，他会以为我们弄丢了。
                // 判据取自报价单的 native_audio，不硬编引擎名单。
                if selectedEngineHasNativeAudio {
                    Text(L10n.key("This tier records its own dialogue — the voice above applies to the draft only"))
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            Picker(L10n.key("Engine"), selection: $engine) {
                ForEach(engines, id: \.id) { e in
                    // 停售的档位标出来但**不隐藏** —— 抹掉会让用户以为
                    // "我昨天用的那档去哪了"，而让他选中再拿 503 更糟。
                    //
                    // 引擎名跟随界面语言。**原来写死 "zh"** —— 英文和西语用户
                    // 在选档这一步看到的是中文档位名，而这是他决定花多少钱的地方。
                    Text(e.isAvailable
                         ? "\(e.displayName(for: uiLang)) · \(e.credits_per_shot)cr"
                         : "\(e.displayName(for: uiLang)) · \(L10n.key("unavailable"))")
                        .tag(e.id)
                }
            }
            .font(.caption)

            // 这一档适合拍什么，一句话。**Web 端选档时有这句，macOS 端此前没有** ——
            // 同一个用户在两端看到的信息量不该不一样，何况这是他决定花多少钱的地方。
            // 只给选中的那一档：菜单里每档都挂一句会把选择器变成一堵墙。
            if let blurb = engines.first(where: { $0.id == engine })?.blurb(for: uiLang) {
                Text(blurb).font(.caption2).foregroundStyle(.secondary)
            }

            // 免费试渲一镜。**这是用户唯一一次看见付费档长什么样的机会** ——
            // 草案是静帧，回答不了"动起来好不好看"，而那正是他付钱买的东西。
            // 免费试渲一镜。**原来的条件是 `engine != "local"`** —— 只在用户
            // 已经选了付费档之后才出现，而默认档就是自研档。线上实测这个功能
            // 被使用 0 次：不是没人要，是给已经决定要买的人发试用。
            // Web 端同一处判断、同一个后果，一起改。
            // 一档付费档都买不到时不挂这个按钮：点下去只会拿一个 400。
            if !sampled, sampleTier != nil {
                HStack(spacing: AppTheme.Spacing.xs) {
                    // 试渲哪一档就说哪一档的名字。**原来只说"付费档长什么样"** ——
                    // 用户看完那一镜，并不知道自己看的是哪一档，也就无从判断
                    // 报价单上哪个数字对应刚才那个画面。
                    Button(sampling ? L10n.key("Rendering a sample shot…")
                                    : L10n.string("See one \(sampleTier?.displayName(for: uiLang) ?? "") shot for real — free, once")) {
                        sampling = true
                        Task {
                            do {
                                guard let tier = sampleTier?.id else { return }
                                try await MetagGateway.sampleShot(id: model.jobId ?? "", engine: tier)
                                sampled = true
                            } catch {
                                sampleError = error.localizedDescription
                            }
                            sampling = false
                        }
                    }
                    .disabled(sampling || model.busy || model.jobId == nil || sampleTier == nil)
                    // 流光只给这一个按钮：它是用户唯一一次免费看见付费档的入口。
                    // 到处都转就成了噪音，谁都不再被看见。
                    .borderBeam(active: !sampling, radius: AppTheme.Radius.xsSm)
                    if sampling { ProgressView().controlSize(.small) }
                }
                .font(.caption2)
            }
            if sampled {
                Text(L10n.key("Sample shot is rendering — it appears in the draft when ready."))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let e = sampleError {
                Text(e).font(.caption2).foregroundStyle(AppTheme.Status.errorColor)
            }
            if engine != "local" {
                Toggle(L10n.key("Use this tier for every shot"), isOn: $allShots).font(.caption2)
                if !allShots {
                    // 说清楚默认会发生什么，而不是让他看完成片再问"为什么画质没变"
                    Text(L10n.key("By default only lip-sync shots use it; the rest stay on the standard tier"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button(L10n.key("Redo the edited shots")) { Task { await model.revise() } }
                    .disabled(model.busy || model.effectiveEdits.isEmpty)
                Spacer()
                // 价钱写在按钮上，不写在按钮旁边。**这是全站一致的规矩** ——
                // 旁边那行会被换行、被挤走、被读屏跳过，而按钮不会。
                // 导演台（MetagDirectorSheet）和 Web 端都是这么做的。
                Button(L10n.string("Produce · \(quote.formatted()) credits")) {
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
