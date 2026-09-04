import SwiftUI

struct CaptionTab: View {
    private enum Output {
        case captions((String?) -> Void)
        case transcript((EditorViewModel.TimelineTranscriptDocument) -> Void)
    }

    @Environment(EditorViewModel.self) var editor
    @Bindable private var account = AccountService.shared
    private let output: Output


    @State private var style: TextStyle = .caption
    @State private var center = AppTheme.Caption.defaultCenter
    @State private var selectedTrackId: String?
    @State private var selectedClipTargets: [String] = []
    /// **这一屏永远是端侧，没有第二档可选。**
    ///
    /// 上一版这是个 `@State`，界面上有个二选一的单选框，
    /// 而"云端"那一档标着 25 credits/小时、带登录门和额度门 ——
    /// 实现却原样调本地那一份（`CloudTranscription` 文件开头自己写着
    /// 「云端转写在 METAG 版本里不存在：音频不出用户设备是产品前提」）。
    ///
    /// 删掉那个 `@State` 而不只是删掉选择器：**让那个状态不可表达，
    /// 比加一条判据去守它结实。** 判据能被绕过，类型不能。
    private let provider: TranscriptionProvider = .local
    @State private var animationPreset: TextAnimation.Preset = .none
    @State private var animationHighlight: TextStyle.RGBA = TextAnimation.defaultHighlight
    @State private var censorProfanity = false
    @State private var maxWords: Int?
    @State private var maxCharacters: Int?
    @State private var maximumGapSeconds = CaptionGapSettings.default.maximumGapSeconds
    @State private var locale: Locale?
    @State private var supportedLocales: [Locale] = []
    @State private var isGenerating = false
    @State private var note: String?
    @State private var templateId: String?
    @State private var templatesExpanded = true
    @State private var sourceExpanded = true
    @State private var settingsExpanded = true
    @State private var styleExpanded = false
    @State private var animationExpanded = false

    private static let previewText = L10n.key("Captions will look like this")
    private static let maxWordRange = 0.0...50.0
    private static let maxCharacterRange = 0.0...200.0

    init(onGeneratedCaptions: @escaping (String?) -> Void) {
        output = .captions(onGeneratedCaptions)
    }

    init(onGeneratedTranscript: @escaping (EditorViewModel.TimelineTranscriptDocument) -> Void) {
        output = .transcript(onGeneratedTranscript)
    }

    private var isTranscriptOnly: Bool {
        if case .transcript = output { true } else { false }
    }

    private var previewConfiguration: CaptionPreviewConfiguration {
        CaptionPreviewConfiguration(
            text: L10n.string(key: Self.previewText),
            style: style,
            center: center,
            preset: animationPreset,
            highlight: animationHighlight
        )
    }

    private var liveTargets: [String] {
        let sel = editor.selectedClipIds
        guard !sel.isEmpty else { return [] }
        return editor.captionTargets(ids: Array(sel)).map(\.id)
    }
    private var isAutoSource: Bool { selectedTrackId == nil && selectedClipTargets.isEmpty }
    private var sourceClipIds: [String] {
        if let selectedTrackId { return editor.captionTargets(trackIds: [selectedTrackId]).map(\.id) }
        return selectedClipTargets   // Auto resolves its source during generation
    }
    private var automaticSourceSummary: String {
        if !selectedClipTargets.isEmpty { return L10n.string("Selected Clips · \(selectedClipTargets.count)") }
        return editor.captionTargets(ids: []).isEmpty ? L10n.string("No audio") : L10n.string("Auto")
    }
    private var effectiveCount: Int {
        isAutoSource ? editor.captionTargets(ids: []).count : sourceClipIds.count
    }
    private var captionTrackIndices: [Int] {
        editor.timeline.tracks.indices.filter { !editor.captionTargets(trackIds: [editor.timeline.tracks[$0].id]).isEmpty }
    }
    /// 转写**一直是端侧**：`CloudTranscription.transcribe` 原样调
    /// `Transcription`（Apple SpeechAnalyzer）。所以没有登录门、没有额度门 ——
    /// 上一版两道门都在，为一个不花钱的功能设的。
    private var canGenerateCaptions: Bool {
        effectiveCount > 0 && !isGenerating
    }

    private static let translateLanguages = [
        (code: "es", promptName: "Spanish"),
        (code: "fr", promptName: "French"),
        (code: "de", promptName: "German"),
        (code: "it", promptName: "Italian"),
        (code: "pt", promptName: "Portuguese"),
        (code: "ja", promptName: "Japanese"),
        (code: "ko", promptName: "Korean"),
        (code: "zh-Hans", promptName: "Chinese"),
        (code: "hi", promptName: "Hindi"),
        (code: "ar", promptName: "Arabic"),
    ]

    private var sourceSummary: String {
        guard let selectedTrackId else { return automaticSourceSummary }
        guard let index = editor.timeline.tracks.firstIndex(where: { $0.id == selectedTrackId }) else { return L10n.string("No track") }
        return L10n.string("\(trackTitle(index)) · \(sourceClipIds.count)")
    }

    var body: some View {
        ZStack {
            VStack(spacing: AppTheme.Spacing.zero) {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.zero) {
                        templateSection
                        sourceSection
                        if isTranscriptOnly {
                            generateBar
                        } else {
                            settingsSection
                            styleSection
                            animationSection
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                if !isTranscriptOnly {
                    generateBar
                }
            }
            if isGenerating {
                AppTheme.Background.surfaceColor.opacity(AppTheme.Opacity.prominent)
                GeneratingOverlay(label: L10n.string("Transcribing…"), size: .preview)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Background.surfaceColor)
        .task {
            guard !isTranscriptOnly else { return }
            guard supportedLocales.isEmpty else { return }
            supportedLocales = (await Transcription.supportedLocales())
                .sorted { languageName($0) < languageName($1) }
        }
        .onAppear {
            rememberSelectedClipTargets()
            if !isTranscriptOnly {
                editor.captionPreviewCenterChange = { center = $0 }
                showCaptionPreview()
            }
        }
        .onDisappear {
            editor.captionPreviewConfiguration = nil
            editor.captionPreviewCenterChange = nil
        }
        .onChange(of: previewConfiguration) { _, _ in showCaptionPreview() }
        .onChange(of: editor.mediaPanelVisible) { _, _ in showCaptionPreview() }
        .onChange(of: editor.selectedClipIds) { _, _ in
            guard !editor.isMarqueeSelecting else { return }
            rememberSelectedClipTargets()
        }
        .onChange(of: editor.isMarqueeSelecting) { wasSelecting, isSelecting in
            guard wasSelecting, !isSelecting else { return }
            rememberSelectedClipTargets()
        }
    }

    /// Templates seed the style, animation, and placement below — the preview and Generate path are unchanged.
    private var templateSection: some View {
        EditorPanelGroup(L10n.key("Template"), isExpanded: $templatesExpanded) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: AppTheme.Spacing.xs),
                    GridItem(.flexible(), spacing: AppTheme.Spacing.xs),
                ],
                spacing: AppTheme.Spacing.xs
            ) {
                ForEach(CaptionTemplate.all) { templateCell($0) }
            }
            if !editor.captionTextClipIds.isEmpty {
                Button(action: applyTemplateToExistingCaptions) {
                    Text(L10n.string("Apply to Existing Captions"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.capsule(.secondary))
                .focusable(false)
                .disabled(selectedTemplate == nil)
                .help(L10n.string("Restyle the captions already on the timeline. Undoable as one step."))
            }
        }
    }

    private var selectedTemplate: CaptionTemplate? {
        CaptionTemplate.all.first { $0.id == templateId }
    }

    private func applyTemplateToExistingCaptions() {
        guard let template = selectedTemplate else { return }
        let count = editor.applyCaptionTemplate(template)
        note = count == 0 ? "No captions to restyle." : "Restyled \(count) caption\(count == 1 ? "" : "s")."
    }

    private func templateCell(_ template: CaptionTemplate) -> some View {
        let selected = templateId == template.id
        return Button {
            apply(template)
        } label: {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(template.name)
                    .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                    .lineLimit(1)
                Text(template.tagline)
                    .font(.system(size: AppTheme.FontSize.xxs))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(AppTheme.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(
                AppTheme.Background.raisedColor, cornerRadius: AppTheme.Radius.sm, border: selected ? AppTheme.Accent.timecodeColor : AppTheme.Border.subtleColor, borderWidth: selected ? AppTheme.BorderWidth.medium : AppTheme.BorderWidth.hairline
            )
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(template.tagline)
    }

    private func apply(_ template: CaptionTemplate) {
        templateId = template.id
        style = template.style
        animationPreset = template.animation.preset
        animationHighlight = template.animation.highlight ?? TextAnimation.defaultHighlight
        center = template.center
        styleExpanded = true
        animationExpanded = true
    }

    private var sourceSection: some View {
        EditorPanelGroup(
            L10n.string("Source"),
            isExpanded: $sourceExpanded,
            headerAccessory: {
                if !isTranscriptOnly {
                    captionPreviewToggle
                }
            }
        ) {
            InspectorRow(
                label: L10n.string("Source"),
                labelHelp: L10n.string("Uses selected clips when available, otherwise all captionable audio. Choose a track to limit captions."),
                onReset: {
                    selectedTrackId = nil
                    selectedClipTargets = []
                }
            ) { sourceMenu }
            InspectorRow(label: L10n.string("Mode")) { localOnlyNote }
        }
    }

    private var captionPreviewToggle: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text(L10n.string("Preview"))
                .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(AppTheme.Text.secondaryColor)
            Toggle(
                String(),
                isOn: Binding(
                    get: { editor.captionPreviewEnabled },
                    set: { editor.captionPreviewEnabled = $0 }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(AppTheme.Text.primaryColor.opacity(AppTheme.Opacity.strong))
            .accessibilityLabel(L10n.string("Preview"))
        }
        .help(L10n.string("Preview"))
    }

    private var settingsSection: some View {
        EditorPanelGroup(L10n.string("Settings"), isExpanded: $settingsExpanded) {
            InspectorRow(label: L10n.string("Language"), onReset: { locale = nil }) {
                Menu {
                    Button(L10n.string("Auto")) { locale = nil }
                    if !supportedLocales.isEmpty {
                        Divider()
                        ForEach(supportedLocales, id: \.identifier) { loc in
                            Button(languageName(loc)) { locale = loc }
                        }
                    }
                } label: { EditorMenuValue(text: locale.map(languageName) ?? L10n.string("Auto"), expanded: true) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).focusable(false)
                .frame(maxWidth: .infinity)
            }
            InspectorRow(
                label: L10n.string("Max words"),
                labelHelp: L10n.string("Cap the words shown per caption. None fits each line to the box."),
                onReset: { maxWords = nil }
            ) {
                ScrubbableNumberField(
                    value: Double(maxWords ?? 0),
                    range: Self.maxWordRange,
                    dragValueAdjustment: { $0.rounded() },
                    displayTextOverride: { $0 < 1 ? L10n.string("None") : nil },
                    onChanged: updateMaxWords,
                    onCommit: updateMaxWords
                )
                .accessibilityLabel(L10n.string("Max words"))
            }
            InspectorRow(
                label: L10n.string("Max characters"),
                labelHelp: L10n.string("Cap characters per caption, including spaces and punctuation. A single word may exceed the limit."),
                onReset: { maxCharacters = nil }
            ) {
                ScrubbableNumberField(
                    value: Double(maxCharacters ?? 0),
                    range: Self.maxCharacterRange,
                    dragValueAdjustment: { $0.rounded() },
                    displayTextOverride: { $0 < 1 ? L10n.string("None") : nil },
                    onChanged: updateMaxCharacters,
                    onCommit: updateMaxCharacters
                )
                .accessibilityLabel(L10n.string("Max characters"))
            }
            InspectorRow(
                label: L10n.string("Close gaps"),
                labelHelp: L10n.string("Extends captions across short gaps and holds the final caption."),
                onReset: {
                    maximumGapSeconds = CaptionGapSettings.default.maximumGapSeconds
                }
            ) {
                ScrubbableNumberField(
                    value: maximumGapSeconds,
                    range: CaptionGapSettings.maximumGapRange,
                    displayMultiplier: 1_000,
                    format: "%.0f",
                    valueSuffix: " ms",
                    dragSensitivity: 10,
                    dragValueAdjustment: { ($0 / 0.05).rounded() * 0.05 },
                    onChanged: { maximumGapSeconds = $0 },
                    onCommit: { maximumGapSeconds = $0 }
                )
                .accessibilityLabel(L10n.string("Close gaps"))
            }
            InspectorRow(label: L10n.string("Censor profanity"), onReset: { censorProfanity = false }) {
                Toggle(String(), isOn: $censorProfanity)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .accessibilityLabel(L10n.string("Censor profanity"))
                    .tint(AppTheme.Text.primaryColor.opacity(AppTheme.Opacity.strong))
            }
        }
    }

    private var sourceMenu: some View {
        Menu {
            Button {
                selectedTrackId = nil
            } label: {
                Label(automaticSourceSummary, systemImage: selectedTrackId == nil ? "checkmark" : "")
            }

            Divider()

            if captionTrackIndices.isEmpty {
                Text(L10n.string("No Tracks"))
            } else {
                ForEach(captionTrackIndices, id: \.self) { index in
                    if editor.timeline.tracks.indices.contains(index) {
                        let track = editor.timeline.tracks[index]
                        let count = editor.captionTargets(trackIds: [track.id]).count
                        let clipCount = count == 1 ? L10n.string("1 clip") : L10n.string("\(count) clips")
                        Button {
                            selectedTrackId = track.id
                        } label: {
                            Label(
                                L10n.string("\(trackTitle(index)) · \(clipCount)"),
                                systemImage: selectedTrackId == track.id ? "checkmark" : ""
                            )
                        }
                    }
                }
            }
        } label: {
            EditorMenuValue(text: sourceSummary, expanded: true)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).focusable(false)
        .frame(maxWidth: .infinity)
    }

    /// **那个"云端"档在卖一个我们故意不做的东西。**
    ///
    /// `CloudTranscription` 文件开头自己写着：「云端转写在 METAG 版本里不存在：
    /// 音频不出用户设备是产品前提，不是可选项」，实现原样调本地那一份。
    /// 而界面上它标着「自动识别语言、更准、能分辨说话人、**25 credits/小时**」，
    /// 未登录灰掉、额度为 0 灰掉，`onReset` 还把用户推到这一档。
    ///
    /// 三件事一起发生：**给不存在的功能标了价、为不花钱的功能设了两道门、
    /// 而且把我们最强的那条承诺（音频不出你的机器）说成了一条收费劣势。**
    ///
    /// 删掉那一档，把那句话翻过来当它本来的样子。
    private var localOnlyNote: some View {
        Text(L10n.string("Transcribed on this Mac — your audio never leaves it, and it costs no credits."))
            .font(.system(size: AppTheme.FontSize.xs))
            .foregroundStyle(AppTheme.Text.secondaryColor)
            .fixedSize(horizontal: false, vertical: true)
    }


    private func rememberSelectedClipTargets() {
        let targets = liveTargets
        guard !targets.isEmpty || editor.focusedPanel != .media else { return }
        selectedClipTargets = targets
    }

    private func trackTitle(_ index: Int) -> String {
        editor.timelineTrackDisplayLabel(at: index)
    }

    private func languageName(_ loc: Locale) -> String {
        AppLocalization.shared.activeLocale.localizedString(forIdentifier: loc.identifier)
            ?? loc.identifier(.bcp47)
    }

    private func translationLanguageName(_ identifier: String) -> String {
        AppLocalization.shared.activeLocale.localizedString(forLanguageCode: identifier)
            ?? identifier
    }

    private var styleSection: some View {
        TextStyleControls(
            selection: TextStyleSelection(styles: [style], fallback: .caption),
            defaults: .caption,
            styleExpanded: $styleExpanded,
            groupsExpandedByDefault: false,
            actions: styleActions,
            afterAlignment: { captionPositionRow },
            afterColor: { EmptyView() }
        )
    }

    private var captionPositionRow: some View {
        InspectorRow(
            label: L10n.string("Position"),
            onReset: { center = AppTheme.Caption.defaultCenter }
        ) {
            HStack(spacing: AppTheme.Spacing.sm) {
                captionPositionField(
                    value: center.x,
                    canvasLength: max(1, editor.timeline.width),
                    label: "X",
                    onChange: { center.x = $0 }
                )
                captionPositionField(
                    value: center.y,
                    canvasLength: max(1, editor.timeline.height),
                    label: "Y",
                    onChange: { center.y = $0 }
                )
            }
            .fixedSize()
        }
    }

    private func captionPositionField(
        value: CGFloat,
        canvasLength: Int,
        label: String,
        onChange: @escaping (CGFloat) -> Void
    ) -> some View {
        ScrubbableNumberField(
            value: Double(value),
            range: -10...10,
            displayMultiplier: Double(canvasLength),
            format: "%.0f",
            fieldWidth: AppTheme.EditorPanel.compactNumericFieldWidth,
            trailingLabel: label,
            onChanged: { onChange(CaptionPreviewPlacement.snappedCoordinate($0)) }
        ) {
            onChange(CaptionPreviewPlacement.snappedCoordinate($0))
        }
    }

    private var styleActions: TextStyleEditingActions {
        TextStyleEditingActions(
            apply: { _, mutation in mutation(&style) },
            commit: { _, mutation in mutation(&style) },
            commitColor: { _, mutation in mutation(&style) },
            cancelPending: { _ in },
            cancelFontPreview: { originalFont in
                if let originalFont { style.fontName = originalFont }
            }
        )
    }

    private var animationSection: some View {
        EditorPanelGroup(L10n.string("Animation"), isExpanded: $animationExpanded) {
            CaptionPresetGallery(selection: $animationPreset, highlight: animationHighlight)
            if animationPreset.usesHighlight {
                InspectorRow(
                    label: L10n.string("Highlight"),
                    labelHelp: L10n.string("Color for the active word."),
                    onReset: { animationHighlight = TextAnimation.defaultHighlight }
                ) {
                    ColorField(displayColor: animationHighlight.swiftUIColor, onUserChange: { animationHighlight = TextStyle.RGBA($0) })
                }
            }
        }
    }

    /// **不带价钱** —— 端侧转写不花额度。上一版按钮上写着
    /// 「Transcribe · N credits」，那个数是为一个不存在的付费档估的。
    private var generateLabel: String {
        isTranscriptOnly ? L10n.string("Transcribe") : L10n.string("Generate")
    }

    private var agentMenu: some View {
        EditorAgentMenu(
            help: L10n.string("Let Agent create captions for you. Choose a predefined task, or ask Agent in the chat.")
        ) {
            Button {
                captionTask("remove filler words (um, uh, er, like, you know) from the captions, keeping each caption's timing unchanged.")
            } label: { Label(L10n.string("Remove filler words"), systemImage: "text.badge.minus") }
            Button {
                captionTask("fix any misspelled names, brand names, or technical jargon in the captions using the surrounding context, keeping timing unchanged.")
            } label: { Label(L10n.string("Fix names & jargon"), systemImage: "checkmark.bubble") }
            Button {
                captionTask("add relevant emoji to the captions, keeping the text and timing otherwise unchanged.")
            } label: { Label(L10n.string("Add emoji"), systemImage: "face.smiling") }
            Menu {
                ForEach(Self.translateLanguages, id: \.code) { language in
                    Button(translationLanguageName(language.code)) {
                        captionTask("translate the captions to \(language.promptName), keeping each caption's timing unchanged.")
                    }
                }
            } label: { Label(L10n.string("Translate"), systemImage: "globe") }
        }
    }

    private func captionTask(_ task: String) {
        handoff("If the timeline has no captions yet, transcribe the spoken audio and add captions on word boundaries first. Then \(task)")
    }

    private func handoff(_ prompt: String) {
        let service = editor.agentService
        service.newChat()
        service.draft = prompt
        editor.agentPanelVisible = true
    }

    private var generateBar: some View {
        EditorActionFooter(message: note) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Spacer(minLength: AppTheme.Spacing.zero)
                Button(action: generate) {
                    Text(generateLabel)
                        .lineLimit(1)
                }
                .buttonStyle(.capsule(.prominent))
                .fixedSize()
                .focusable(false)
                .disabled(!canGenerateCaptions)

                if !isTranscriptOnly {
                    agentMenu
                }
            }
        }
    }

    private func generate() {
        note = nil
        let sourceIds = sourceClipIds
        if selectedTrackId != nil && sourceIds.isEmpty {
            note = L10n.string("No audio selected.")
            return
        }
        let request = EditorViewModel.CaptionRequest(
            sourceClipIds: sourceIds,
            autoDetect: isAutoSource,
            style: style,
            center: center,
            censorProfanity: censorProfanity,
            locale: locale,
            maxWords: maxWords,
            maxCharacters: maxCharacters,
            gapSettings: CaptionGapSettings(maximumGapSeconds: maximumGapSeconds) ?? .default,
            provider: provider,
            animation: TextAnimation(preset: animationPreset, highlight: animationHighlight)
        )
        Task {
            isGenerating = true
            defer { isGenerating = false }
            do {
                // 这里原来先查登录、再估价、再查余额 —— 全部为一个
                // **不存在的付费档**设的。端侧转写不花额度，直接走。
                switch output {
                case .transcript(let onGeneratedTranscript):
                    let transcript = try await editor.timelineTranscript(
                        for: request
                    )
                    if transcript.rows.isEmpty {
                        note = L10n.string("No speech detected.")
                    } else {
                        onGeneratedTranscript(transcript)
                    }
                case .captions(let onGeneratedCaptions):
                    let createdIds = try await editor.generateCaptions(for: request)
                    if createdIds.isEmpty {
                        note = L10n.string("No speech detected.")
                    } else {
                        let groupId = createdIds.lazy.compactMap {
                            editor.clipFor(id: $0)?.captionGroupId
                        }.first
                        editor.captionPreviewEnabled = false
                        onGeneratedCaptions(groupId)
                    }
                }
            } catch {
                note = localizedCaptionError(error)
            }
        }
    }

    private func showCaptionPreview() {
        editor.captionPreviewConfiguration = !isTranscriptOnly && editor.mediaPanelVisible
            ? previewConfiguration
            : nil
    }

    private func updateMaxCharacters(_ value: Double) {
        let count = Int(value.rounded())
        maxCharacters = count > 0 ? count : nil
    }

    private func updateMaxWords(_ value: Double) {
        let count = Int(value.rounded())
        maxWords = count > 0 ? count : nil
    }


    private func localizedCaptionError(_ error: Error) -> String {
        guard let error = error as? TranscriptionError else { return error.localizedDescription }
        switch error {
        case .unsupportedLocale(let identifier):
            return L10n.string("On-device transcription is not available for \(identifier).")
        case .modelInstallFailed(let reason):
            return L10n.string("Could not install the on-device speech model: \(reason)")
        case .decodeFailed:
            return L10n.string("Could not parse transcription result.")
        case .audioExtractionFailed(let reason):
            return L10n.string("Audio extraction failed: \(reason)")
        case .analysisFailed(let reason):
            return L10n.string("Transcription failed: \(reason)")
        }
    }
}
