import SwiftUI

struct MusicSection: View {
    @Environment(EditorViewModel.self) var editor
    @Bindable private var account = AccountService.shared
    @Binding var isExpanded: Bool

    @State private var selectedModelId: String?
    @State private var mode: MusicGenerationSubmission.Mode = .videoToMusic
    @State private var prompt: String = ""
    @State private var textDuration: Double = 90
    @State private var isGenerating = false
    @State private var generatingLabel = L10n.key("Generating…")
    @State private var note: String?

    private var models: [AudioModelConfig] {
        AudioModelConfig.allModels.filter { $0.inputs.contains(.video) && $0.category == .music }
    }

    private var model: AudioModelConfig? {
        if let id = selectedModelId, let m = models.first(where: { $0.id == id }) { return m }
        return models.first
    }

    private func supportsTextMode(_ m: AudioModelConfig) -> Bool {
        m.category == .music && m.inputs.contains(.text)
    }

    /// Text mode only when the selected model supports text-to-music.
    private var effectiveMode: MusicGenerationSubmission.Mode {
        (model.map(supportsTextMode) ?? false) ? mode : .videoToMusic
    }
    private var isTextMode: Bool { effectiveMode == .textToMusic }

    private var textDurationRange: ClosedRange<Double> {
        guard let range = model?.durationRange else { return 1...600 }
        return Double(range.minimum)...Double(range.maximum)
    }

    private var defaultTextDuration: Double {
        Double(model?.durationRange?.defaultValue ?? 90)
    }

    private var source: EditorViewModel.TimelineSpan? { editor.selectedTimelineSpan() }

    private var spanSeconds: Double {
        guard let source else { return 0 }
        return Double(source.frameCount) / Double(max(1, editor.timeline.fps))
    }

    /// Where a text-to-music clip lands: the marked range start, else the playhead.
    private var textPlacementFrame: Int {
        editor.validSelectedTimelineRange?.startFrame ?? editor.currentFrame
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var costDuration: Int {
        isTextMode ? Int(textDuration.rounded()) : Int(spanSeconds.rounded())
    }

    private var estimatedCost: Int? {
        guard let model, costDuration > 0 else { return nil }
        return CostEstimator.audioCost(
            model: model,
            prompt: trimmedPrompt,
            durationSeconds: costDuration,
            input: isTextMode ? .text : .video
        )
    }

    /// 这一行说的是**"还没到时候"还是"这一步过不去"** —— 两件事不该一个颜色。
    ///
    /// 之前所有提示都刷成错误红。而其中最常见的那句
    /// 「说说你想要什么样的音乐」是在他**什么都还没做**的时候出现的：
    /// 打开面板就是一行红字，等于开门先说他错了。
    enum Note: Equatable {
        /// 他还没动手 —— 安静的灰，是引导不是指责。
        case hint(String)
        /// 这一步真的过不去（余额不够、参数不合法）。
        case blocked(String)
        /// **过不去，但不是他做错了 —— 是这台机器还没配好。**
        ///
        /// 「没有可用的音乐模型」原来走 `.blocked`，于是他刚打开面板、
        /// 什么都没做，就看到一句**红字**，而红色在这个产品里的意思是"出事了"。
        /// 更糟的是它**没说下一步** —— 一句红色的死胡同。
        ///
        /// 这一档用平静的灰，而且**必须给一扇门**（去设置里开一个）。
        case setup(String)

        var text: String {
            switch self { case .hint(let t), .blocked(let t), .setup(let t): t }
        }

        /// 能不能按"生成"。**没配好也按不了**，所以它和 `.blocked` 同档。
        var isBlocking: Bool {
            switch self { case .blocked, .setup: true; case .hint: false }
        }

        /// 该不该涂红。**只有"出事了"才红。**
        var isAlarming: Bool { if case .blocked = self { true } else { false } }

        /// 该不该给一扇门。
        var needsSetup: Bool { if case .setup = self { true } else { false } }
    }

    /// **他还没动手的那两种情况。**
    ///
    /// 抽出来是为了让判据能直接问它 —— 上一版判据只会比源码里那一行长什么样，
    /// 把 `.hint` 改成 `.blocked` 它一声不响。
    /// 判据要去解析源码，通常说明源码该长得更清楚一点。
    static func missingInputHint(isTextMode: Bool, promptIsEmpty: Bool, hasSource: Bool) -> Note? {
        if isTextMode {
            return promptIsEmpty ? .hint(L10n.string("Describe the music to generate.")) : nil
        }
        return hasSource ? nil
            : .hint(L10n.string("Add video to the timeline, then mark a range to score only part of it."))
    }

    private var validationNote: Note? {
        guard let model else { return .setup(L10n.string("No music model is set up yet.")) }
        if let hint = Self.missingInputHint(
            isTextMode: isTextMode, promptIsEmpty: trimmedPrompt.isEmpty, hasSource: source != nil
        ) { return hint }
        if isTextMode {
            let params = AudioGenerationParams(
                prompt: trimmedPrompt,
                voice: nil,
                lyrics: nil,
                styleInstructions: nil,
                instrumental: false,
                durationSeconds: costDuration
            )
            if let issue = model.validate(params: params) { return .blocked(issue) }
        } else if let issue = model.validate(spanSeconds: spanSeconds) {
            return .blocked(issue)
        }
        if let cost = estimatedCost, cost > AccountService.shared.remainingCredits,
           AccountService.shared.remainingCredits != nil {
            return .blocked(CostEstimator.localizedInsufficientCredits(
                cost,
                remaining: AccountService.shared.remainingCredits
            ))
        }
        return nil
    }

    private var canGenerate: Bool {
        model != nil && validationNote == nil && !isGenerating
    }

    private var generateLabel: String {
        if let cost = estimatedCost, cost > 0 { return CostEstimator.localizedGenerateLabel(cost) }
        return L10n.string("Generate")
    }

    private var sourceSummary: String {
        guard let source else { return L10n.string("No video") }
        let range = "\(clock(source.startFrame)) – \(clock(source.startFrame + source.frameCount)) · \(String(format: "%.1fs", spanSeconds))"
        return editor.validSelectedTimelineRange == nil
            ? L10n.string("Whole timeline · \(range)")
            : range
    }

    var body: some View {
        musicSection
            .overlay {
                if isGenerating {
                    ZStack {
                        AppTheme.Background.surfaceColor.opacity(AppTheme.Opacity.prominent)
                        GeneratingOverlay(label: generatingLabel, size: .preview)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(AppTheme.Background.surfaceColor)
    }

    private var musicSection: some View {
        EditorPanelGroup(
            L10n.string("Music"),
            isExpanded: $isExpanded
        ) {
            sourceControls
            modelControl
            promptControl
            musicActions
        }
    }

    @ViewBuilder
    private var sourceControls: some View {
        if model.map(supportsTextMode) == true {
            InspectorRow(
                label: L10n.string("Input"),
                labelAlignment: .leading,
                onReset: { mode = .videoToMusic }
            ) {
                Menu {
                    Button(L10n.string("Video to Music")) { mode = .videoToMusic }
                    Button(L10n.string("Text to Music")) { mode = .textToMusic }
                } label: { EditorMenuValue(text: modeLabel(effectiveMode), expanded: true) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).focusable(false)
                .frame(maxWidth: .infinity)
            }
        }
        if isTextMode {
            InspectorRow(
                label: L10n.string("Duration"),
                labelHelp: L10n.string("Length of the generated music. It's placed at the playhead, or at the marked range start."),
                labelAlignment: .leading,
                onReset: { textDuration = defaultTextDuration }
            ) {
                ScrubbableNumberField(
                    value: textDuration,
                    range: textDurationRange,
                    format: "%.0f",
                    valueSuffix: " s",
                    dragValueAdjustment: { $0.rounded() },
                    onChanged: { textDuration = $0.rounded() }
                ) { textDuration = $0.rounded() }
            }
        } else {
            InspectorRow(
                label: L10n.string("Video"),
                labelHelp: L10n.string("Uses the whole timeline by default. Mark a range on the timeline to score only that span."),
                labelAlignment: .leading
            ) { valueText(sourceSummary) }
        }
    }

    private func modeLabel(_ m: MusicGenerationSubmission.Mode) -> String {
        switch m {
        case .videoToMusic: L10n.string("Video to Music")
        case .textToMusic: L10n.string("Text to Music")
        }
    }

    private var modelControl: some View {
        InspectorRow(
            label: L10n.string("Model"),
            labelAlignment: .leading,
            onReset: { selectModel(nil) }
        ) {
            Menu {
                ForEach(models, id: \.id) { m in
                    Button(m.displayName) { selectModel(m) }
                }
            } label: {
                EditorMenuValue(text: model?.displayName ?? L10n.string("None"), expanded: true)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).focusable(false)
            .frame(maxWidth: .infinity)
        }
    }

    private func selectModel(_ selectedModel: AudioModelConfig?) {
        selectedModelId = selectedModel?.id
        guard let selectedModel = selectedModel ?? models.first else { return }
        if let range = selectedModel.durationRange,
           !(Double(range.minimum)...Double(range.maximum)).contains(textDuration) {
            textDuration = Double(range.defaultValue)
        } else if let durations = selectedModel.durations,
                  !durations.contains(Int(textDuration.rounded())) {
            textDuration = Double(durations.first ?? 90)
        }
    }

    private var promptControl: some View {
        InspectorRow(label: L10n.string("Prompt"), labelAlignment: .leading) {
            TextField(text: $prompt, axis: .vertical) {
                Text(verbatim: model?.promptLabel ?? String())
            }
                .textFieldStyle(.plain)
                .lineLimit(2...5)
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.primaryColor)
                .padding(AppTheme.Spacing.smMd)
                .editorValueField()
        }
    }

    private var musicActions: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            // `note` 是真跑失败之后那句，一定是红的；
            // `validationNote` 分两档 —— 引导用灰，过不去才用红。
            if let message = note.map(Note.blocked) ?? validationNote {
                Text(message.text)
                    .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(message.isAlarming
                                     ? AppTheme.Status.errorColor
                                     : AppTheme.Text.secondaryColor)
                    .fixedSize(horizontal: false, vertical: true)
                // **说了过不去，就得说往哪走。** 一句话加一扇门，
                // 而不是一句红色的死胡同。
                if message.needsSetup {
                    Button {
                        SettingsWindowController.shared.show(tab: .models)
                    } label: {
                        Label(L10n.string("Add models…"), systemImage: "plus")
                            .font(.system(size: AppTheme.FontSize.xs))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.Accent.brand)
                    .pointerStyle(.link)
                }
            }
            HStack(spacing: AppTheme.Spacing.sm) {
                Spacer(minLength: AppTheme.Spacing.zero)
                Button(action: generate) {
                    Text(generateLabel)
                        .lineLimit(1)
                }
                .buttonStyle(.capsule(.prominent))
                .fixedSize()
                .focusable(false)
                .disabled(!canGenerate || !account.aiAllowed)
                .help(account.aiAllowed ? String() : L10n.string("Sign in to generate"))

                agentMenu
            }
        }
    }

    private func valueText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.medium))
            .foregroundStyle(AppTheme.Text.tertiaryColor)
            .lineLimit(1)
    }

    private func clock(_ frame: Int) -> String {
        let total = Double(frame) / Double(max(1, editor.timeline.fps))
        let m = Int(total) / 60
        let s = Int(total) % 60
        return String(format: "%d:%02d", m, s)
    }

    private var agentMenu: some View {
        EditorAgentMenu(
            help: L10n.string("Let Agent generate music for you. Choose a starter, or ask Agent in the chat.")
        ) {
            Button {
                musicTask("Score my timeline with music that matches the visuals. Use a video-to-music model on the full timeline span so the music follows the edit, and place it on an audio track.")
            } label: { Label(L10n.string("Generate music for the timeline"), systemImage: "music.note") }
            Menu {
                ForEach(["Cinematic", "Upbeat", "Ambient", "Tense", "Lo-fi"], id: \.self) { mood in
                    Button(mood) {
                        musicTask("Generate \(mood.lowercased()) music for my timeline and place it on an audio track aligned to the edit.")
                    }
                }
            } label: { Label(L10n.string("Mood"), systemImage: "slider.horizontal.3") }
        }
    }

    private func musicTask(_ prompt: String) {
        let service = editor.agentService
        service.newChat()
        service.draft = prompt
        editor.agentPanelVisible = true
    }

    private func generate() {
        note = nil
        guard let model else { return }
        let trimmed = trimmedPrompt.isEmpty ? nil : trimmedPrompt
        let submission: MusicGenerationSubmission
        if isTextMode {
            let frameCount = max(1, Int(textDuration * Double(max(1, editor.timeline.fps))))
            submission = MusicGenerationSubmission(
                mode: .textToMusic, model: model, prompt: trimmed,
                source: .init(startFrame: textPlacementFrame, frameCount: frameCount),
                spanSeconds: textDuration, name: nil
            )
        } else {
            guard let source else { return }
            submission = MusicGenerationSubmission(
                mode: .videoToMusic, model: model, prompt: trimmed,
                source: source, spanSeconds: spanSeconds, name: nil
            )
        }

        isGenerating = true
        generatingLabel = (isTextMode ? MusicGenerationSubmission.Phase.generating : .exporting).label
        Task {
            do {
                try await submission.run(
                    service: editor.generationService,
                    projectURL: editor.projectURL,
                    editor: editor,
                    onPhase: { generatingLabel = $0.label },
                    onFinished: { isGenerating = false }
                )
            } catch {
                note = error.localizedDescription
                isGenerating = false
            }
        }
    }
}
