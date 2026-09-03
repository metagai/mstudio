import SwiftUI

/// 自动导演面板：一个主题 → 分镜 → 报价 → 用户确认 → 生成 → 落进媒体库。
/// 报价确认是产品承诺：`awaiting_approval` 必须展示报价并等用户点，这里不存在自动 approve 的分支。
struct MetagDirectorSheet: View {
    @Binding var isPresented: Bool

    @Environment(EditorViewModel.self) private var editor
    @Bindable private var account = AccountService.shared

    @State private var presets: [MetagDirector.Preset] = []
    @State private var presetId: String?
    @State private var topic = ""
    @State private var siteURL = ""
    @State private var run: MetagDirector.Run?
    @State private var busy = false
    @State private var note: String?
    @State private var adoptedJobId: String?

    private var preset: MetagDirector.Preset? { presets.first { $0.id == presetId } }

    private var canStart: Bool {
        guard let preset, !busy, !topic.trimmed.isEmpty else { return false }
        return !preset.needsURL || !siteURL.trimmed.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            header
            if let run {
                runBody(run)
            } else {
                setupBody
            }
            if let note {
                Text(note)
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Status.errorColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
        .padding(AppTheme.Spacing.lg)
        .frame(width: AppTheme.Director.sheetWidth)
        .background(AppTheme.Background.surfaceColor)
        .task {
            guard presets.isEmpty else { return }
            presets = (try? await MetagGateway.directorPresets()) ?? []
        }
        .task(id: pollKey) { await poll() }
        .onChange(of: run?.job_id) { _, jobId in adopt(jobId: jobId) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "film.stack")
                .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.Accent.primary)
            Text(L10n.string("Auto Director"))
                .font(.system(size: AppTheme.FontSize.lg, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.Text.primaryColor)
            Spacer(minLength: 0)
            if account.isSignedIn {
                Text(L10n.string("\(account.remainingCredits.formatted()) credits"))
                    .font(.system(size: AppTheme.FontSize.xs))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }
        }
    }

    // MARK: - Setup

    private var setupBody: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: AppTheme.Spacing.sm), GridItem(.flexible(), spacing: AppTheme.Spacing.sm)],
                spacing: AppTheme.Spacing.sm
            ) {
                ForEach(presets) { presetCard($0) }
            }
            if preset?.needsURL == true {
                TextField(L10n.string("Product site, e.g. https://your-product.com"), text: $siteURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: AppTheme.FontSize.sm))
            }
            TextField(L10n.string("What should it be about?"), text: $topic, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...3)
                .font(.system(size: AppTheme.FontSize.sm))
            Text(L10n.string("Every paid step quotes first. Nothing is billed until you approve."))
                .font(.system(size: AppTheme.FontSize.xs))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
        }
    }

    private func presetCard(_ item: MetagDirector.Preset) -> some View {
        let selected = presetId == item.id
        return Button {
            guard item.isSupported else { return }
            presetId = item.id
        } label: {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(item.name)
                    .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Text(item.isSupported ? item.tagline : L10n.string("Available in METAG Studio only"))
                    .font(.system(size: AppTheme.FontSize.xxs))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                    .lineLimit(2)
                Text(L10n.string("~\(Int(item.target_seconds).formatted())s · \(item.estimated_cost_credits.formatted()) credits · ~\(max(1, item.estimated_wait_seconds / 60).formatted()) min"))
                    .font(.system(size: AppTheme.FontSize.xxs))
                    .foregroundStyle(AppTheme.Accent.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Spacing.sm)
            .cardSurface(
                selected ? AppTheme.Accent.primary.opacity(AppTheme.Opacity.faint) : AppTheme.Background.raisedColor,
                cornerRadius: AppTheme.Radius.sm,
                border: selected ? AppTheme.Accent.primary : AppTheme.Border.subtleColor,
                borderWidth: selected ? AppTheme.BorderWidth.medium : AppTheme.BorderWidth.hairline
            )
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!item.isSupported)
        .opacity(item.isSupported ? AppTheme.Opacity.opaque : AppTheme.Opacity.muted)
    }

    // MARK: - Run

    @ViewBuilder
    private func runBody(_ run: MetagDirector.Run) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            stageBar(run)
            budgetBar(run)
            if let site = run.artifacts.site, let title = site.title {
                Text(site.frame_id == nil
                     ? "Fetched \(title) — no key visual, using an AI first frame."
                     : "Fetched \(title) — using its key visual as the first frame.")
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
            }
            if let narrations = run.artifacts.storyboard?.narrations, !narrations.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        ForEach(Array(narrations.enumerated()), id: \.offset) { index, line in
                            Text("\(index + 1). \(line)")
                                .font(.system(size: AppTheme.FontSize.xs))
                                .foregroundStyle(AppTheme.Text.secondaryColor)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(AppTheme.Spacing.sm)
                }
                .frame(maxHeight: AppTheme.Director.storyboardMaxHeight)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                        .fill(AppTheme.Background.raisedColor)
                )
            }
            if run.isAwaitingApproval, let quote = run.artifacts.quote {
                quoteCard(quote)
            }
            if let error = run.error {
                // 这一句来自网关的 `run.error`。2026-09-02 之前它可能是
                // 「分镜流 HTTP 500：{上游响应体前 200 字}」—— 状态码和上游报错
                // 正文原样红字给用户。**已在源头改掉**（gateway/src/director.rs）：
                // 那几句现在都说清是谁的问题、他能做什么，原文只进网关日志。
                Text(error)
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Status.errorColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if run.status == "done" {
                Text(L10n.string("Done. Shots are landing in the media library."))
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Status.successColor)
            }
        }
    }

    private func stageBar(_ run: MetagDirector.Run) -> some View {
        let stages = MetagDirector.stages(for: run.pipeline)
        let current = stages.firstIndex { $0.id == run.stage } ?? 0
        return HStack(spacing: AppTheme.Spacing.xxs) {
            ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                let done = run.status == "done" || index < current
                Text(stage.label)
                    .font(.system(size: AppTheme.FontSize.xxs, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(index == current && !done ? AppTheme.Background.baseColor : AppTheme.Text.secondaryColor)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.xs)
                            .fill(stageFill(index: index, current: current, done: done))
                    )
            }
        }
    }

    private func stageFill(index: Int, current: Int, done: Bool) -> Color {
        if done { return AppTheme.Accent.primary.opacity(AppTheme.Opacity.faint) }
        if index == current { return AppTheme.Accent.primary }
        return AppTheme.Background.raisedColor
    }

    private func budgetBar(_ run: MetagDirector.Run) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
            HStack {
                Text(L10n.string("Budget"))
                Spacer(minLength: 0)
                Text(L10n.string("\(run.spent_credits.formatted()) / \(run.budget_credits.formatted()) credits")).monospacedDigit()
            }
            .font(.system(size: AppTheme.FontSize.xxs))
            .foregroundStyle(AppTheme.Text.tertiaryColor)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.Background.raisedColor)
                    Capsule()
                        .fill(AppTheme.Accent.primary)
                        .frame(width: geo.size.width * spentFraction(run))
                }
            }
            .frame(height: AppTheme.Director.progressBarHeight)
        }
    }

    private func spentFraction(_ run: MetagDirector.Run) -> Double {
        guard run.budget_credits > 0 else { return 0 }
        return min(1, Double(run.spent_credits) / Double(run.budget_credits))
    }

    private func quoteCard(_ quote: MetagDirector.Run.Quote) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
            if let reason = quote.reason {
                Text(reason)
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(L10n.string("\(MetagDirector.stageLabel(quote.stage)) costs \(quote.cost_credits.formatted()) credits — \(quote.engine), \(quote.shots.formatted()) shots. Billed only after you approve."))
                .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(AppTheme.Text.primaryColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.sm)
        .cardSurface(
            AppTheme.Accent.primary.opacity(AppTheme.Opacity.faint),
            cornerRadius: AppTheme.Radius.sm,
            border: AppTheme.Accent.primary.opacity(AppTheme.Opacity.medium)
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            if let run, !run.isTerminal {
                Button(L10n.string("Stop")) { act { try await MetagGateway.cancelDirectorRun(run.id) } }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .disabled(busy)
            }
            Spacer(minLength: 0)
            Button(L10n.string("Close")) { isPresented = false }
                .buttonStyle(.plain)
                .focusable(false)
            if run == nil {
                Button(account.isSignedIn ? L10n.key("Start") : L10n.key("Sign In to Start"), action: start)
                    .buttonStyle(.editorPrimary)
                    .focusable(false)
                    .disabled(account.isSignedIn ? !canStart : busy)
            }
            if let run, run.isAwaitingApproval {
                Button(L10n.string("Approve \((run.artifacts.quote?.cost_credits ?? 0).formatted()) Credits")) {
                    act { try await MetagGateway.approveDirectorRun(run.id) }
                }
                .buttonStyle(.editorPrimary)
                .focusable(false)
                .disabled(busy)
            }
            if let run, run.status == "failed" || run.status == "cancelled" {
                Button(L10n.string("Start Over")) { reset() }
                    .buttonStyle(.editorPrimary)
                    .focusable(false)
            }
        }
    }

    // MARK: - Actions

    private var pollKey: String { run.map { "\($0.id)|\($0.status)" } ?? "" }

    /// 只在 running 时轮询：等确认与终态都不打扰服务端。
    private func poll() async {
        guard let current = run, current.status == "running" else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: AppTheme.Director.pollInterval)
            guard !Task.isCancelled else { return }
            guard let next = try? await MetagGateway.directorRun(current.id) else { continue }
            guard !Task.isCancelled, run?.id == next.id else { return }
            run = next
            if next.status != "running" { return }
        }
    }

    private func start() {
        // 这里没有菜单可弹（是个动作，不是一颗按钮），所以**说一句，不擅自跳**。
        // 它以前直接打开 Google 授权页。
        guard account.isSignedIn else {
            note = L10n.string("Sign in to METAG to generate.")
            return
        }
        guard let preset else { return }
        note = nil
        busy = true
        let topic = topic.trimmed
        let url = siteURL.trimmed
        Task {
            defer { busy = false }
            do {
                run = try await MetagGateway.startDirectorRun(
                    preset: preset.id,
                    topic: topic,
                    url: preset.needsURL ? url : nil
                )
            } catch {
                note = error.localizedDescription
            }
        }
    }

    private func act(_ operation: @escaping () async throws -> MetagDirector.Run) {
        note = nil
        busy = true
        Task {
            defer { busy = false }
            do {
                run = try await operation()
                await account.refreshMetagAccount()
            } catch {
                note = error.localizedDescription
            }
        }
    }

    /// 生成任务一出现就交给既有的 GenerationService：下载/入库/撤销逻辑只有一处。
    private func adopt(jobId: String?) {
        guard let jobId, let run, adoptedJobId != jobId else { return }
        adoptedJobId = jobId
        editor.generationService.adoptBackendJob(
            backendJobId: jobId,
            shots: run.artifacts.quote?.shots ?? preset?.shots ?? 4,
            prompt: run.topic,
            model: run.artifacts.quote?.engine ?? "local",
            editor: editor
        )
    }

    private func reset() {
        run = nil
        adoptedJobId = nil
        note = nil
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
