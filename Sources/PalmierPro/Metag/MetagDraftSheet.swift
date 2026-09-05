import SwiftUI

extension Notification.Name {
    /// 引导页那颗主按钮：**先看一眼你的片子**，不是先登录。
    /// 用通知而不是共享状态：发起的是首屏，接住的是媒体面板，两者互不认识。
    static let metagStartDraft = Notification.Name("metagStartDraft")
    /// 从首页打开他上一条片子。**首页那一刻还没有项目**，
    /// 所以和起草一样：先建工程、开编辑器，再由面板接手把片子铺上时间线。
    static let metagOpenFilm = Notification.Name("metagOpenFilm")
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
    /// 用户亲口挑的镜数。**nil = 由 METAG 决定** —— 那是默认，也是对的默认。
    ///
    /// 原来这里写死 4，于是一句"一镜到底"的提示词照样出四镜。
    @Published var chosenShots: Int?

    /// 已经知道的镜数：他挑的，或者分镜回来之后真实的那个。
    var knownShots: Int? { chosenShots ?? job?.shots.count.nonZero }
    /// 网关给的这一条片子的报价。为空就退回本地按档位单价算 ——
    /// 那是第二份真源，只在问不到价时用。
    /// 这句话旁边该不该有一扇门，以及是哪一扇。
    ///
    /// `note` 是一个字符串 —— 到了界面那一层，"为什么失败"已经没了。
    /// 而**只有一种失败是转化那一刻**：他想出片、余额不够。
    enum NoteDoor: Equatable { case topUp }
    @Published var noteDoor: NoteDoor?

    /// 判据要能摆出"刚撞了墙"这个状态，而设置它的那段藏在 `approve` 的 catch 里。
    func noteDoorForTesting(_ error: Error) {
        if case MetagGateway.Failure.insufficientCredits = error { noteDoor = .topUp }
    }
    func clearNoteForTesting() { note = nil; noteDoor = nil }

    @Published var quote: MetagGateway.Quote?
    @Published private(set) var jobId: String?
    @Published private(set) var job: MetagGateway.Job?
    @Published private(set) var busy = false
    @Published private(set) var note: String?
    /// 逐镜改过的旁白。key 是镜号 —— 只有真变了的才发出去。
    @ObservationIgnored private var askedForQuote = false
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

    /// **分镜写到哪儿就露到哪儿。**
    ///
    /// `shots` 要等整个 storyboard 步跑完（实测 20–37 秒）才有内容，
    /// 而网关的 `storyboard_preview` 是一句一句到的 —— 同一份分镜的两个时刻。
    /// 之前只读前者，于是那几十秒里空格子上一个字都没有。
    ///
    /// 落定之后以 `shots` 为准：它是这条片子最终的那一份。
    var narrations: [String] {
        let settled = job?.shots.map(\.narration) ?? []
        return settled.isEmpty ? (job?.storyboard_preview ?? []) : settled
    }
    /// 当前旁白人格。网关认不出的值一律当没有 —— 宁可不显示，也不显示一个错的。
    var narrator: MetagNarrator? { job?.narrator.flatMap(MetagNarrator.init(rawValue:)) }
    var ready: Bool { job?.status == "done" && !(job?.shots.isEmpty ?? true) }
    /// 已经取回的首帧，按镜号。**等待期间就开始填** ——
    /// 首帧比成片早得多，没有理由让用户对着转圈干等。
    @Published private(set) var frames: [Int: NSImage] = [:]

    /// 第一张画面**落到他屏幕上**的那一刻，距离它在世界上就绪隔了多久。
    ///
    /// 只记一次，跟着 `draft_seen` 一起报上去。
    private(set) var firstFrameLagMs: Int?

    private func fetchFrames(_ id: String, _ job: MetagGateway.Job) async {
        guard let names = job.first_frames else { return }
        for (i, name) in names.enumerated() where frames[i] == nil {
            guard let url = try? await MetagGateway.download(
                job: id, name: name, to: FileManager.default.temporaryDirectory),
                  let img = NSImage(contentsOf: url) else { continue }
            let wasEmpty = frames.isEmpty
            frames[i] = img
            // **就绪到看见，中间那段第一次能量了。**
            //
            // 判据落在"图真的进了 `frames`"这一刻，不落在"我问到了"——
            // 那两件事之间还隔着一次下载，而那一段也算在他等的时间里。
            if wasEmpty { noteFirstFrameLag(job) }
        }
    }

    /// 网关还没发这个字段（或首帧还没出现）就不记 ——
    /// **宁可这一格没有数，也不要编一个出来。**
    private func noteFirstFrameLag(_ job: MetagGateway.Job) {
        noteLag(readyAt: job.first_frame_at_ms)
    }

    /// 判据直接喂那个时间戳 —— 造一整个 `Job` 只为测一个减法，
    /// 测的就变成"我会不会拼 JSON"了。
    func noteLagForTesting(readyAt: Int64?) { noteLag(readyAt: readyAt) }

    /// 判据要能摆出「分镜写到一半」这个状态，而 `job` 是 private(set)。
    func applyJobForTesting(_ j: MetagGateway.Job) { job = j }

    private func noteLag(readyAt: Int64?) {
        guard firstFrameLagMs == nil, let readyAt else { return }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let lag = now - readyAt
        // 机器时钟跟服务端对不齐是常事：负数或大得离谱的数是钟的问题，不是产品的。
        guard lag >= 0, lag < 10 * 60 * 1000 else { return }
        firstFrameLagMs = Int(lag)
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

    /// 他粘/拖进来的图。上传换 frame_id 之后作为 `assets` 交给导演。
    @Published var imageURLs: [URL] = []

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
        do {
            // 图先上传换 frame_id。**哪张没传上去要说出来** ——
            // 悄悄少一张，他会以为导演没看懂他的参考图。
            var assets: [String] = []
            var failed = 0
            for url in imageURLs {
                if let id = try? await MetagGateway.uploadFrame(url) { assets.append(id) } else { failed += 1 }
            }
            if failed > 0 { note = PromptPaste.Notice.imageFailed.text }
            // 他没挑就不传 —— 让读过提示词的那一方去定。
            let id = try await MetagGateway.preview(prompt: prompt, shots: chosenShots, assets: assets)
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
        busy = true; note = nil; noteDoor = nil
        defer { busy = false }
        do {
            let job = try await MetagGateway.approvePreview(id: id, engine: engine, allShots: allShots)
            // **网关收下了才算。** 记在按钮上的话，一次失败的批准会让转化率
            // 凭空变好而钱一分没进来 —— 而我们会照着那个数去排下一步的工。
            // 带上这一单的档位和报价：报价有没有改变他的选择，只能在这里看出来。
            // 报价没拿到就**不报这一格**，而不是报个 0 ——
            // 0 会被当成"这一单没花钱"混进均价里，而我们要照那个数排下一步的工。
            var meta: [String: Any] = ["engine": engine, "quoted": quote != nil]
            if let credits = quote?.options.first(where: { $0.engine == engine })?.total_credits {
                meta["credits"] = credits
            }
            MetagFunnel.track(.paid, meta: meta)
            return job
        } catch {
            note = error.localizedDescription
            // **撞墙那一刻要留一扇门，不是留一句指路。**
            //
            // 30 天真数：撞上额度墙 4 人 → 打开收银台 1 人，**丢掉 75%**，
            // 这是有真人走过的步骤里转化最差的一格。
            // 而这句话原来是 `Not enough credits — top up or subscribe in
            // Settings › Account.` —— 它自己的注释写着「这是转化那一刻，
            // 而它原来是个句号」，然后把句号换成了**一句指路**。
            //
            // 指路和门的区别：指路要他记住一条路径、退出这一屏、自己找过去，
            // 而他此刻手里正有一条看完的草案。**门就在这句话旁边。**
            if case MetagGateway.Failure.insufficientCredits = error {
                noteDoor = .topUp
            }
            return nil
        }
    }

    /// 报价问一次就够。失败一律吞掉：问不到价不该挡住免费草案。
    private func quoteOnce() {
        guard quote == nil, !askedForQuote, let shots = knownShots else { return }
        askedForQuote = true
        Task { [prompt] in
            let lang = AppLocalization.shared.selection.identifier.map { String($0.prefix(2)) } ?? "en"
            quote = try? await MetagGateway.quote(prompt: prompt, shots: shots, lang: lang)
        }
    }

    /// 等第一张画面的时候追紧一点，拿到之后退回去。
    ///
    /// **这段等待里唯一能救场的就是第一张画面。** 网关那侧约第 13 秒就绪，
    /// 而固定 4 秒一轮的话（加上从国内打过去实测 1.0–1.5 秒的来回，
    /// 一轮实际 5.2 秒），轮询点落在 0 / 5.2 / 10.4 / 15.6 ——
    /// **他第 15.6 秒才知道，再下载完约第 17.4 秒才看见**。
    /// 白丢 2.6 秒（最坏 5.2 秒），跟模型快不快无关，是我们自己的架构损耗。
    ///
    /// 终局是走网关那条 WebSocket（它早就在了，Mac 一行都没接）。
    /// 在那之前这是十分之一代价的修法：只在**还没有任何一张画面**的时候追紧，
    /// 那段最多二十来秒，多打的请求是个位数；首帧一到就退回 4 秒。
    ///
    /// **不要"顺手统一成 4 秒"。** 追紧只为救第一张画面那一刻；
    /// 整场都追是拿网关的负载换一个已经拿到的东西。
    nonisolated static func pollInterval(hasFrame: Bool) -> Duration {
        hasFrame ? .seconds(4) : .milliseconds(1200)
    }

    private func poll(_ id: String) async {
        // 从数轮数改成看时钟 —— 间隔不再是常数，轮数就不再等于时长。
        let deadline = ContinuousClock.now.advanced(by: .seconds(480))
        while ContinuousClock.now < deadline {
            if let j = try? await MetagGateway.job(id) {
                job = j
                // **知道真镜数了才问价。**
                //
                // 原来在起草那一刻就按客户端那个 4 去问 —— 而镜数现在由服务端定，
                // 我们那时根本不知道会切几镜，报出来的是个假设。
                // 分镜是第一个阶段，这个数在等待的早期就到了，
                // 所以他仍然是"在决定之前就知道代价"，只是这回那个代价是真的。
                //
                // 只问一次：轮询每 4 秒一轮，每轮都问会打爆报价接口。
                quoteOnce()
                await fetchFrames(id, j)
                if j.status == "done" || j.status == "failed" {
                    // **草案真的到他屏幕上了** —— 判据落在"渲完并且这一页还在"，
                    // 不落在"我们提交成功了"。那两件事之间就是流失。
                    if j.status == "done" {
                        // `first_frame_lag_ms`：首帧就绪到他真的看见，隔了多久。
                        // **这是那 4.4 秒第一次进报表** —— 在此之前它连量都量不了。
                        MetagFunnel.track(.draftSeen, meta: firstFrameLagMs.map {
                            ["first_frame_lag_ms": $0]
                        })
                    }
                    return
                }
            }
            try? await Task.sleep(for: Self.pollInterval(hasFrame: !frames.isEmpty))
        }
        note = L10n.string("The draft is taking too long — try again in a moment.")
    }
}

struct MetagDraftSheet: View {
    /// 首屏那句话。他已经写过一次了，**不该再写一遍** ——
    /// 而且写完立刻就开跑：面板一打开草案就在起，他等的是片子不是表单。
    var initialPrompt: String?
    var initialAssets: [URL] = []

    @Environment(\.dismiss) private var dismiss
    @Environment(EditorViewModel.self) private var editor
    @StateObject private var model = MetagDraftModel()
    @State private var engines: [MetagGateway.Pricing.Engine] = []
    @State private var engine = MetagDraftSheet.fallbackEngineID
    // 免费试渲：一人一次，所以只有"没用过 / 正在渲 / 已经用过"三种
    @State private var sampling = false
    @State private var sampled = false
    @State private var sampleError: String?
    /// 引擎名跟界面语言走 —— 此前写死 "zh"，英文和西语用户在**决定花多少钱的那一步**
    /// 看到的是中文档位名。
    private var uiLang: String { AppLocalization.shared.gatewayLanguage }
    /// 全片使用所选引擎。**默认关** —— 默认只有口播镜用贵引擎，其余降到 local。
    @State private var allShots = false
    /// 粘进来的稿子。**卡片是纯界面** —— `draft()` 之前会并回 `model.prompt`。
    @State private var attachments: [PromptAttachment] = []
    @State private var notices: [PromptPaste.Notice] = []
    @FocusState private var promptFocused: Bool

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
    /// 出片按钮上那个数字。**问不到权威价就不印数。**
    ///
    /// ## 它原来印的是镜数
    ///
    /// 上一版是 `guard allShots else { return model.knownShots ?? 1 }` ——
    /// 不勾"全片使用"时（**这是默认**）返回的是**镜数**，被印成
    /// 「Produce · 6 credits」。而同一屏自己写着默认路由是
    /// 「口播镜用所选付费档，其余走 local」：选 veo（90cr/镜）、6 镜的片子，
    /// 按钮写 6，实扣约 184。
    ///
    /// **他按下去、扣完、去看余额少了 184 —— 在他心里这就是我们偷偷加价。**
    /// 这不需要任何故障，是默认路径上每天都会发生的事。
    ///
    /// ## 也不再拿本地单价乘一遍
    ///
    /// `?? perShot * shots` 那个兜底同样是编数字：网关改了档位价，
    /// 本地那份照旧报旧价，而他按下去扣的是新价。
    ///
    /// 混合路由这一侧客户端**算不出来**（没有逐镜口播标记），
    /// 所以只有两种诚实的结果：网关报了价就印它，没有就不印。
    /// 产品里已经有这个写法（`MetagVoiceSheet.cloneLabel`：问不到价只写「克隆」）。
    /// 出片按钮上写什么。网关报了价就印它，没有就不印。
    nonisolated static func produceLabel(credits: Int?) -> String {
        credits.map { L10n.string("Produce · \($0.formatted()) credits") } ?? L10n.string("Produce")
    }

    private var quote: Int? {
        guard allShots else { return nil }
        return model.quote?.options.first { $0.engine == engine }?.total_credits
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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            HStack(spacing: AppTheme.Spacing.xs) {
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
        .padding(.top, AppTheme.Spacing.xs)
    }

    private var blocked: String? {
        func down(_ id: String) -> Bool { engines.first { $0.id == id }?.isAvailable == false }
        if down(Self.fallbackEngineID) { return L10n.key("Generation is unavailable right now — try again later, nothing will be charged") }
        if down(engine) { return L10n.key("That engine is temporarily unavailable — pick another") }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.mdLg) {
            Text(L10n.string("See the draft first, then decide"))
                .font(.system(size: AppTheme.FontSize.xl, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(AppTheme.Text.primaryColor)
            if model.jobId == nil {
                promptStage
            } else if model.ready {
                draftStage
            } else {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
                    // 说的是**谁在干什么**，而不是干到百分之几。
                    // 原来这里是一个转圈加一句"正在起草"；那句话曾经写着"约 40 秒"，
                    // 而实测 53–97 秒 —— 被告知 40 秒却等了 90 秒的人会觉得产品坏了。
                    // 现在不给数字，给的是这一刻真的有人在做的那件事。
                    MetagCrewView(
                        stage: model.job?.stage,
                        shotCount: model.knownShots
                    )
                    // 幕布紧跟在班底后面：**上一句说谁在干活，这一块就给出他干的活。**
                    // 报价排最后 —— 他此刻想看的是画面，不是账。
                    //
                    // 先按真实镜数摆好空格，每一格填进来都是一次真的到货。
                    // 原来是"有几张摆几张"，于是这 90 秒里他看不出片子有多长、
                    // 还差多少 —— 一排会变多的邮票，讲不出"我的片子正在成形"。
                    filmStrip

                    // 等待期间就把代价说了。**这 90 秒本来是空的**，而他等完
                    // 之后要做的第一个决定就是"要不要花这笔钱" —— 让他在等的时候
                    // 就已经知道，而不是等完才第一次听到数字。
                    if let q = model.quote, let rec = q.recommended {
                        quotePreview(rec, why: q.why(uiLang))
                    }
                }
            }
            if let n = model.note {
                MetagNoteRow(note: n, door: model.noteDoor)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(width: AppTheme.MetagDraft.sheetWidth)
        .task {
            engines = (try? await MetagGateway.pricing().engines) ?? []
        }
        .onAppear(perform: seedIfNeeded)
    }

    /// 带着首屏那句话进来的话，填好并立刻开跑。
    private func seedIfNeeded() {
        guard let initialPrompt, model.prompt.isEmpty, model.jobId == nil else { return }
        model.prompt = initialPrompt
        attachments = initialAssets.map {
            PromptAttachment(title: $0.lastPathComponent, kind: .image($0))
        }
        Task { await model.draft() }
    }

    /// 镜数。**默认由 METAG 定，而这是对的默认。**
    ///
    /// 原来这里是一个从 4 起步的旋钮 —— 于是每个用户都"选了" 4，
    /// 包括那些写了"一镜到底"的人。只有读过提示词的那一方有资格决定切几镜。
    ///
    /// 想自己定的人仍然能定：点一下就变成旋钮。**能力没少，默认变对了。**
    @ViewBuilder
    private var shotCountControl: some View {
        HStack(spacing: AppTheme.Spacing.smMd) {
            if let chosen = model.chosenShots {
                Stepper(
                    L10n.string("\(chosen.formatted()) shots"),
                    value: Binding(get: { chosen }, set: { model.chosenShots = $0 }),
                    in: 1...8
                )
                .fixedSize()
                Button(L10n.string("Let METAG decide")) { model.chosenShots = nil }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.Accent.brand)
            } else {
                Text(L10n.string("METAG picks how many shots"))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                Button(L10n.string("I'll choose")) { model.chosenShots = 4 }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.Accent.brand)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: AppTheme.FontSize.sm))
    }

    /// 一句话或者一份稿子，有一样就能起草。
    private var canDraft: Bool {
        !PromptPaste.composed(line: model.prompt, attachments: attachments).isEmpty
            && PromptPaste.overflow(line: model.prompt, attachments: attachments) == nil
    }

    private func paste() -> Bool {
        let outcome = PromptPaste.read(existing: attachments)
        guard !outcome.attachments.isEmpty || !outcome.notices.isEmpty else { return false }
        apply(outcome)
        return true
    }

    /// 拖进来和粘进来落**同一张卡** —— 两个入口给出不同的结果，
    /// 而用户并不知道自己刚才用的是哪一个。
    private func apply(_ outcome: PromptPaste.Outcome) {
        attachments.append(contentsOf: outcome.attachments)
        if let text = outcome.insert { model.prompt += text }
        notices = outcome.notices
    }

    private var promptStage: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            TextField(L10n.string("Say what you want to film, in one line"), text: $model.prompt, axis: .vertical)
                .lineLimit(2...4)
                // 一键成片这一屏最可能被粘进来的就是一份大纲。收成卡片，
                // 别把输入框撑成一堵墙。
                .focused($promptFocused)
                .promptPaste(isFocused: promptFocused) { paste() }

            PromptAttachmentBar(
                attachments: $attachments,
                overflow: PromptPaste.overflow(line: model.prompt, attachments: attachments),
                notices: notices
            )
            shotCountControl
            // 把代价说在前面：草案免费。不说清楚的话，用户不敢点。
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: AppTheme.FontSize.xs))
                Text(L10n.string("Drafts are free — no credits charged"))
                    .font(.system(size: AppTheme.FontSize.sm))
            }
            .foregroundStyle(AppTheme.Status.successColor)
            HStack {
                Spacer()
                Button(L10n.string("Cancel")) { dismiss() }
                    .buttonStyle(.capsule(.secondary, size: .regular))
                Button(L10n.string("Draft it")) {
                    // 卡片在这一刻兑现：稿子并回 prompt（接口那一侧始终只有一个
                    // prompt），图片交给 `assets`。
                    model.prompt = PromptPaste.composed(line: model.prompt, attachments: attachments)
                    model.imageURLs = PromptPaste.images(in: attachments)
                    attachments = []
                    Task { await model.draft() }
                }
                    .buttonStyle(.capsule(.prominent, size: .regular))
                    .disabled(model.busy || !canDraft)
            }
        }
    }

    /// 那块幕布。**等待时和落定后是同一块** —— 他刚看着它一格格填满，
    /// 落定的那一刻它不该消失。
    ///
    /// 原来草案一好，这块画面整个被一堆输入框换掉了 ——
    /// **幕布在最该拉开的那一刻合上了**，他刚看完的东西不见了，
    /// 眼前是一张表。
    private var filmStrip: some View {
        MetagFilmStrip(
            shots: model.knownShots ?? 0,
            frames: model.frames,
            narrations: model.narrations
        )
    }

    private var draftStage: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            // **幕布真正拉开的那一刻。**
            //
            // 等待时它是一格格填满的场记板；片子好了，它就该换成片子本身。
            // 草案的 `preview.mp4` 一直都在（网关在发、web 的幕布在播），
            // 而 Mac 之前连这个字段都没解 —— 于是"先看一眼"给的是
            // 一排静态图：那不是"看一眼"，那是"看一眼它的证据"。
            //
            // 拿不到那条片子就退回场记板，不留空白。
            if let preview = model.job?.preview {
                MetagDraftPlayer(jobId: model.jobId ?? "", name: preview)
            } else {
                filmStrip
            }

            ForEach(Array(model.narrations.enumerated()), id: \.offset) { i, text in
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    TextField(L10n.string("Shot \((i + 1).formatted()) narration"), text: Binding(
                        get: { model.edits[i] ?? text },
                        set: { model.edits[i] = $0 }
                    ))
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                    Toggle(L10n.string("Different composition"), isOn: Binding(
                        get: { model.rerolls.contains(i) },
                        set: { on in if on { model.rerolls.insert(i) } else { model.rerolls.remove(i) } }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                }
            }
            Divider()
            // 音色摆在引擎上面：用户先关心"谁在讲我的片子"，再关心画质档位。
            // 免费必须写出来，否则他不敢点 —— 而"敢试"正是这个交互的全部价值。
            if let current = model.narrator {
                Picker(L10n.string("Narrator voice"), selection: Binding(
                    get: { current },
                    set: { n in Task { await model.swapNarrator(n) } }
                )) {
                    ForEach(MetagNarrator.allCases, id: \.self) { n in
                        // 写死 "zh"：英文/西语界面的旁白音色下拉全是中文
                        // （「电影感 · 沉稳男声」）。同一文件 615 行的引擎名
                        // 刚从写死 "zh" 改成 uiLang，这一处漏了。
                        Text(n.displayName(for: uiLang)).tag(n)
                    }
                }
                .font(.system(size: AppTheme.FontSize.sm))
                .disabled(model.busy)
                Text(L10n.string("Changing the voice is free — only the narration is re-recorded"))
                    .font(.system(size: AppTheme.FontSize.xs)).foregroundStyle(AppTheme.Text.mutedColor)
                // 选中的档位自带音轨时，这个音色只作用于草案。**说出来** ——
                // 否则用户挑了半天旁白，成片里说话的是模型自己，他会以为我们弄丢了。
                // 判据取自报价单的 native_audio，不硬编引擎名单。
                if selectedEngineHasNativeAudio {
                    Text(L10n.string("This tier records its own dialogue — the voice above applies to the draft only"))
                        .font(.system(size: AppTheme.FontSize.xs)).foregroundStyle(AppTheme.Status.warningColor)
                }
            }
            Picker(L10n.string("Engine"), selection: $engine) {
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
            .font(.system(size: AppTheme.FontSize.sm))

            // 这一档适合拍什么，一句话。**Web 端选档时有这句，macOS 端此前没有** ——
            // 同一个用户在两端看到的信息量不该不一样，何况这是他决定花多少钱的地方。
            // 只给选中的那一档：菜单里每档都挂一句会把选择器变成一堵墙。
            if let blurb = engines.first(where: { $0.id == engine })?.blurb(for: uiLang) {
                Text(blurb).font(.system(size: AppTheme.FontSize.xs)).foregroundStyle(AppTheme.Text.mutedColor)
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
                    // 外层 `if` 已经保证了 `sampleTier != nil`，而这一段只在
                    // 草案就绪后渲染、`jobId` 不可能为 nil —— 那两个条件从没起过作用。
                    // **留着一个不做事的门，下一个人会以为门在那儿。**
                    .disabled(sampling || model.busy)
                    // 流光只给这一个按钮：它是用户唯一一次免费看见付费档的入口。
                    // 到处都转就成了噪音，谁都不再被看见。
                    .borderBeam(active: !sampling, radius: AppTheme.Radius.xsSm)
                    if sampling { ProgressView().controlSize(.small) }
                }
                .font(.system(size: AppTheme.FontSize.xs))
            }
            if sampled {
                Text(L10n.string("Sample shot is rendering — it appears in the draft when ready."))
                    .font(.system(size: AppTheme.FontSize.xs)).foregroundStyle(AppTheme.Text.mutedColor)
            }
            if let e = sampleError {
                Text(e).font(.system(size: AppTheme.FontSize.xs)).foregroundStyle(AppTheme.Status.errorColor)
            }
            if engine != "local" {
                Toggle(L10n.string("Use this tier for every shot"), isOn: $allShots)
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                if !allShots {
                    // 说清楚默认会发生什么，而不是让他看完成片再问"为什么画质没变"
                    Text(L10n.string("By default only lip-sync shots use it; the rest stay on the standard tier"))
                        .font(.system(size: AppTheme.FontSize.xs)).foregroundStyle(AppTheme.Text.mutedColor)
                }
            }
            HStack {
                // **改过才出现。** 原来它永远摆在那儿、永远是灰的（没改东西时
                // `effectiveEdits` 是空的），而它就在"出片"旁边 ——
                // 用户第一眼看到的是一颗死按钮，没有任何一处说它为什么死。
                // 一颗常年灰着的按钮教给用户的是"这个 app 有坏按钮"。
                //
                // 而它本来就是上下文动作：改了旁白、或者勾了"换个构图"，
                // 它才有意义。改了它就出现 —— 那一刻他正好需要它。
                if !model.effectiveEdits.isEmpty {
                    Button(L10n.string("Redo \(model.effectiveEdits.count.formatted()) shots")) {
                        Task { await model.revise() }
                    }
                    .buttonStyle(.capsule(.secondary, size: .regular))
                    .disabled(model.busy)
                }
                Spacer()
                // 价钱写在按钮上，不写在按钮旁边。**这是全站一致的规矩** ——
                // 旁边那行会被换行、被挤走、被读屏跳过，而按钮不会。
                // 导演台（MetagDirectorSheet）和 Web 端都是这么做的。
                Button(Self.produceLabel(credits: quote)) {
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
                .buttonStyle(.capsule(.prominent, size: .regular))
                .disabled(model.busy || blocked != nil)
            }
            if let blocked {
                // 说出原因，而不是给一个禁用的按钮让用户猜
                Text(blocked).font(.system(size: AppTheme.FontSize.xs)).foregroundStyle(AppTheme.Status.warningColor)
            }
        }
    }
}
