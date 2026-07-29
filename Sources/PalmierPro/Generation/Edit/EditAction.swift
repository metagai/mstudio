import Foundation

enum EditAction {
    case upscale
    case edit
    case rerun
    case lipSync
    case reframe
    case generateMusic
    case generateSFX
    case createVideo
    case enhanceDraft

    static let editMaxDurationSeconds: Double = 10.0

    var requiresPaidPlan: Bool {
        switch self {
        case .upscale, .edit, .lipSync, .reframe: true
        case .generateMusic, .generateSFX, .rerun, .createVideo, .enhanceDraft: false
        }
    }

    func group(for mediaType: ClipType) -> AIEditActionGroup {
        switch self {
        case .generateMusic, .generateSFX:
            .audio
        case .rerun where mediaType == .audio:
            .audio
        case .upscale, .edit, .rerun, .lipSync, .reframe, .createVideo, .enhanceDraft:
            .enhance
        }
    }

    @MainActor
    static func available(for asset: MediaAsset, effectiveDurationOverride: Double? = nil) -> [EditAction] {
        let candidates: [EditAction]
        switch asset.type {
        case .image: candidates = [.upscale, .edit, .rerun, .createVideo]
        case .video:
            candidates = [
                .upscale, .edit, .rerun, .lipSync, .reframe, .enhanceDraft,
                .generateMusic, .generateSFX,
            ]
        case .audio, .text: candidates = [.upscale, .edit, .rerun]
        case .lottie, .sequence, .subtitle: candidates = []
        }
        return candidates.filter {
            $0.catalogSupported
                && $0.availability(for: asset, effectiveDurationOverride: effectiveDurationOverride).isAvailable
        }
    }

    /// 目录里没有能干这件事的模型，这个入口就不该出现。
    ///
    /// 上游的候选表是按素材类型写死的，不问后端；我们的网关只卖它登记过的那几档，
    /// 于是每加一个上游功能就多一个点了没反应的菜单项。**灰着或点了没反应的按钮
    /// 比没有这个按钮更廉价**，而逐个删是会烂的 —— 上游每加一个我们就要再删一次。
    /// 判断落在这一处，网关卖什么就出现什么。
    @MainActor
    var catalogSupported: Bool {
        let catalog = ModelCatalog.shared
        switch self {
        case .upscale: return !catalog.upscale.isEmpty
        case .edit: return !catalog.image.isEmpty
        case .createVideo, .lipSync, .reframe: return !catalog.video.isEmpty
        case .generateMusic, .generateSFX: return !catalog.audio.isEmpty
        // 重跑用的是素材自己那一档；草案增强另有 asset.canEnhanceDraft 把关。
        case .rerun, .enhanceDraft: return true
        }
    }

    @MainActor
    func availability(for asset: MediaAsset, effectiveDurationOverride: Double? = nil) -> EditActionAvailability {
        switch self {
        case .enhanceDraft:
            guard asset.canEnhanceDraft else {
                return .disabled(reason: L10n.string("Draft already enhanced or cache unavailable"))
            }
            return .available

        case .upscale:
            guard asset.type == .video || asset.type == .image else {
                return .disabled(reason: L10n.string("Upscale only works on video or images"))
            }
            if asset.isGenerating {
                return .disabled(reason: L10n.string("Generation in progress"))
            }
            return .available

        case .reframe:
            guard asset.type == .video else {
                return .disabled(reason: L10n.string("Reframe only works on video"))
            }
            if asset.isGenerating {
                return .disabled(reason: L10n.string("Generation in progress"))
            }
            guard let model = VideoModelConfig.reframe else {
                return .disabled(reason: L10n.string("Reframe model not available"))
            }
            let duration = effectiveDurationOverride ?? asset.resolvedDuration
            if let error = model.validateReframeDuration(duration) {
                return .disabled(reason: error)
            }
            return .available

        case .lipSync:
            guard asset.type == .video else {
                return .disabled(reason: L10n.string("Lip Sync only works on video"))
            }
            if asset.isGenerating {
                return .disabled(reason: L10n.string("Generation in progress"))
            }
            guard let model = VideoModelConfig.lipSync else {
                return .disabled(reason: L10n.string("Lip Sync model not available"))
            }
            let duration = effectiveDurationOverride ?? asset.resolvedDuration
            if let error = model.validateSourceDuration(duration) {
                return .disabled(reason: error)
            }
            guard !UpscaleModelConfig.models(for: asset.type).isEmpty else {
                return .disabled(reason: "No upscale model available")
            }
            return .available

        case .edit:
            switch asset.type {
            case .video:
                guard VideoModelConfig.edit != nil else {
                    return .disabled(reason: L10n.string("Edit model not available"))
                }
                let duration = effectiveDurationOverride ?? asset.resolvedDuration
                guard duration > 0 else {
                    return .disabled(reason: L10n.string("Loading video metadata…"))
                }
                guard duration <= EditAction.editMaxDurationSeconds else {
                    return .disabled(reason: L10n.string(
                        "Edit supports up to \(Int(EditAction.editMaxDurationSeconds))s (this is \(Int(duration.rounded()))s)"
                    ))
                }
            case .image:
                break // images have no duration constraint
            case .audio:
                return .disabled(reason: L10n.string("Edit doesn't support audio"))
            case .text:
                return .disabled(reason: L10n.string("Edit doesn't support text"))
            case .lottie:
                return .disabled(reason: L10n.string("Edit doesn't support Lottie"))
            case .sequence:
                return .disabled(reason: L10n.string("Edit doesn't support sequences"))
            case .subtitle:
                return .disabled(reason: L10n.string("Edit doesn't support subtitles"))
            }
            if asset.isGenerating {
                return .disabled(reason: L10n.string("Generation in progress"))
            }
            guard EditSubmitter.editSeed(for: asset) != nil else {
                return .disabled(reason: "No editing model available")
            }
            return .available

        case .generateMusic:
            return Self.videoAudioAvailability(
                for: asset,
                kind: .music,
                effectiveDurationOverride: effectiveDurationOverride
            )

        case .generateSFX:
            return Self.videoAudioAvailability(
                for: asset,
                kind: .sfx,
                effectiveDurationOverride: effectiveDurationOverride
            )

        case .createVideo:
            guard asset.type == .image else {
                return .disabled(reason: L10n.string("Create Video only works on images"))
            }
            if asset.isGenerating {
                return .disabled(reason: L10n.string("Generation in progress"))
            }
            guard EditSubmitter.createVideoSeed(for: asset, asReference: false) != nil
                || EditSubmitter.createVideoSeed(for: asset, asReference: true) != nil
            else {
                return .disabled(reason: "No video model accepts a source image")
            }
            return .available

        case .rerun:
            guard asset.isGenerated else {
                return .disabled(reason: L10n.string("Only available for AI-generated media"))
            }
            if asset.isGenerating {
                return .disabled(reason: L10n.string("Generation in progress"))
            }
            guard let modelId = asset.generationInput?.model, ModelRegistry.exists(id: modelId) else {
                return .disabled(reason: L10n.string("Model no longer available"))
            }
            return .available
        }
    }

    @MainActor
    private static func videoAudioAvailability(
        for asset: MediaAsset,
        kind: VideoToAudioEditKind,
        effectiveDurationOverride: Double?
    ) -> EditActionAvailability {
        guard asset.type == .video else {
            let reason = switch kind {
            case .music: L10n.string("Generate Music only works on video")
            case .sfx: L10n.string("Generate SFX only works on video")
            }
            return .disabled(reason: reason)
        }
        if asset.isGenerating {
            return .disabled(reason: L10n.string("Generation in progress"))
        }
        let duration = effectiveDurationOverride ?? asset.resolvedDuration
        guard duration > 0 else {
            return .disabled(reason: L10n.string("Loading video metadata…"))
        }
        guard let model = kind.model else {
            return .disabled(reason: L10n.string("\(kind.providerName) model not available"))
        }
        if let err = model.validate(spanSeconds: duration) {
            return .disabled(reason: err)
        }
        return .available
    }
}

enum AIEditActionGroup {
    case enhance
    case audio
}

enum EditActionAvailability: Equatable {
    case available
    case disabled(reason: String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var reason: String? {
        if case .disabled(let r) = self { return r }
        return nil
    }
}
