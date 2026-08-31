import Foundation
import Combine

enum ModelKind: Sendable {
    case video(VideoModelConfig)
    case image(ImageModelConfig)
    case audio(AudioModelConfig)
    case upscale(UpscaleModelConfig)
}

enum ModelRegistry {
    @MainActor static var byId: [String: ModelKind] { ModelCatalog.shared.byId }

    @MainActor static func exists(id: String) -> Bool { byId[id] != nil }


    @MainActor static func displayName(for id: String) -> String {
        switch byId[id] {
        case .video(let m): m.displayName
        case .image(let m): m.displayName
        case .audio(let m): m.displayName
        case .upscale(let m): m.displayName
        case .none: id
        }
    }

    @MainActor static func providerIconKey(for id: String) -> String? {
        switch byId[id] {
        case .video(let m): m.entry.providerIconKey
        case .image(let m): m.entry.providerIconKey
        case .audio(let m): m.entry.providerIconKey
        case .upscale(let m): m.entry.providerIconKey
        case .none: nil
        }
    }
}

@Observable
@MainActor
final class ModelCatalog {
    static let shared = ModelCatalog()
    private static let supportedCatalogVersion: Double = 4

    private(set) var video: [VideoModelConfig] = []
    private(set) var image: [ImageModelConfig] = []
    private(set) var audio: [AudioModelConfig] = []
    private(set) var upscale: [UpscaleModelConfig] = []
    private(set) var byId: [String: ModelKind] = [:]
    private(set) var isLoaded: Bool = false
    private(set) var lastError: String?

    @ObservationIgnored private var didConfigure = false

    private init() {}

    /// Video models come from `/api/v1/pricing` — the same endpoint that owns what we charge,
    /// so a picker price can never disagree with the bill. That feed has no image/audio/upscale
    /// tiers, so those three stay empty until the gateway offers them.
    func configure() {
        guard !didConfigure else { return }
        didConfigure = true
        Task { await load() }
    }

    func load() async {
        do {
            let pricing = try await MetagGateway.pricing()
            // 网关按语言给引擎显示名；跟随应用内选择，未指定时回落到系统语言
            let code = AppLocalization.shared.selection.identifier
                ?? Locale.current.language.languageCode?.identifier ?? "en"
            apply(pricing.engines.map { Self.videoEntry(from: $0, language: code) }
                  + (await Self.localEntries()))
        } catch {
            lastError = error.localizedDescription
            Log.generation.error("ModelCatalog load failed: \(error.localizedDescription)")
        }
    }

    /// Not from `/api/v1/pricing`: on-device generation neither bills nor reaches the gateway.
    /// Absent when the models are missing — an option that errors on click is worse than none.
    nonisolated static func localEntries() async -> [CatalogEntry] {
        guard await LocalImageBackend.isAvailable() else { return [] }
        return [
            CatalogEntry(
                id: LocalImageBackend.modelId,
                kind: .image,
                displayName: L10n.key("On-device · Z-Image Turbo"),
                providerName: L10n.key("This Mac"),
                description: L10n.key("No network, no credits. About 3 minutes per image."),
                responseShape: .images,
                uiCapabilities: .image(
                    ImageCaps(
                        // Matches the free-tier i2v render size; generating larger only burns time.
                        resolutions: ["\(LocalImageBackend.defaultWidth)x\(LocalImageBackend.defaultHeight)"],
                        aspectRatios: [],
                        qualities: nil,
                        supportsImageReference: false,
                        maxImages: 1
                    )
                ),
                creditsPerImage: ["": 0],
                paidOnly: false
            )
        ]
    }

    /// Billing is flat per shot, and each engine has exactly one duration, so the per-second rate
    /// is `credits_per_shot / duration` — over that one duration it re-multiplies back to the
    /// exact flat price. If the duration is missing we publish no rate at all rather than a
    /// guess: an absent estimate is honest, a wrong one is not.
    nonisolated static func videoEntry(
        from engine: MetagGateway.Pricing.Engine,
        language: String = "en"
    ) -> CatalogEntry {
        // Structured fields win; `spec` parsing is only a fallback for older gateway responses.
        let parsed = parseSpec(engine.spec)
        let seconds = engine.duration_s ?? parsed.seconds
        let resolution = engine.resolution.map { $0.lowercased() } ?? parsed.resolution
        var rate: [String: Double]?
        if let seconds, seconds > 0 {
            rate = ["": Double(engine.credits_per_shot) / Double(seconds)]
        }
        return CatalogEntry(
            id: engine.id,
            kind: .video,
            displayName: engine.displayName(for: language),
            description: engine.spec,
            responseShape: .video,
            uiCapabilities: .video(
                VideoCaps(
                    supportsPrompt: true,
                    durations: seconds.map { [$0] } ?? [],
                    resolutions: resolution.map { [$0] },
                    aspectRatios: [],
                    supportsFirstFrame: false,
                    supportsLastFrame: false,
                    maxReferenceImages: 0,
                    maxReferenceVideos: 0,
                    maxReferenceAudios: 0,
                    maxTotalReferences: nil,
                    maxCombinedVideoRefSeconds: nil,
                    maxCombinedAudioRefSeconds: nil,
                    framesAndReferencesExclusive: false,
                    referenceTagNoun: "reference",
                    requiresSourceVideo: false,
                    maxSourceVideoSeconds: nil,
                    maxSourceVideoResolution: nil,
                    requiredSourceVideoEncoding: nil,
                    requiresReferenceImage: false,
                    requiresReferenceAudio: nil,
                    draftCreditsPerSecond: nil,
                    draftEnhanceCreditsPerSecond: nil,
                    sourceVideoCreditsPerSecond: nil,
                    sourceVideoDraftCreditsPerSecond: nil
                )
            ),
            creditsPerSecond: rate,
            // The gateway gates on credits, not on subscription tier.
            paidOnly: false
        )
    }

    /// Specs look like "480P · 16fps · 3s" or "720P · 24fps · 8s（最高画质）".
    nonisolated static func parseSpec(_ spec: String) -> (resolution: String?, seconds: Int?) {
        func first(_ pattern: String) -> String? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let m = re.firstMatch(in: spec, range: NSRange(spec.startIndex..., in: spec)),
                  let r = Range(m.range(at: 1), in: spec)
            else { return nil }
            return String(spec[r])
        }
        let resolution = first(#"(\d+)\s*[pP]\b"#).map { "\($0)p" }
        let seconds = first(#"(\d+)\s*s\b"#).flatMap(Int.init)
        return (resolution, seconds)
    }

    private func apply(_ entries: [CatalogEntry]) {
        var newVideo: [VideoModelConfig] = []
        var newImage: [ImageModelConfig] = []
        var newAudio: [AudioModelConfig] = []
        var newUpscale: [UpscaleModelConfig] = []
        var newById: [String: ModelKind] = [:]
        newVideo.reserveCapacity(entries.count)
        newImage.reserveCapacity(entries.count)
        newAudio.reserveCapacity(entries.count)
        newUpscale.reserveCapacity(entries.count)
        newById.reserveCapacity(entries.count)

        for entry in entries {
            switch entry.uiCapabilities {
            case .video(let caps):
                let m = VideoModelConfig(entry: entry, caps: caps)
                newVideo.append(m)
                newById[m.id] = .video(m)
            case .image(let caps):
                let m = ImageModelConfig(entry: entry, caps: caps)
                newImage.append(m)
                newById[m.id] = .image(m)
            case .audio(let caps):
                let m = AudioModelConfig(entry: entry, caps: caps)
                newAudio.append(m)
                newById[m.id] = .audio(m)
            case .upscale(let caps):
                let m = UpscaleModelConfig(entry: entry, caps: caps)
                newUpscale.append(m)
                newById[m.id] = .upscale(m)
            }
        }

        self.video = newVideo
        self.image = newImage
        self.audio = newAudio
        self.upscale = newUpscale
        self.byId = newById
        self.isLoaded = true
        self.lastError = nil
    }
}

struct CatalogEntry: Decodable, Sendable {
    let id: String
    let kind: Kind
    let displayName: String
    let providerIconKey: String?
    let providerName: String?
    let description: String?
    let allowedEndpoints: [String]
    let responseShape: ResponseShape
    let uiCapabilities: UICapabilities
    let creditsPerSecond: [String: Double]?
    let audioDiscountRate: [String: Double]?
    let creditsPerImage: [String: Double]?
    let qualities: [String]?
    let audioPricing: AudioPricing?
    let creditsPerSecondUpscale: Double?
    let upscalePricing: UpscalePricing?
    let paidOnly: Bool

    enum Kind: String, Decodable, Sendable { case video, image, audio, upscale }
    enum ResponseShape: String, Decodable, Sendable {
        case video, images, audio, upscaledImage
    }

    enum UICapabilities: Sendable {
        case video(VideoCaps)
        case image(ImageCaps)
        case audio(AudioCaps)
        case upscale(UpscaleCaps)
    }

    enum AudioPricing: Decodable, Sendable {
        case perThousandChars(rate: Double)
        case perSecond(rate: Double, textRate: Double?)
        case flat(price: Double)

        private enum K: String, CodingKey { case mode, rate, textRate, price }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            switch try c.decode(String.self, forKey: .mode) {
            case "perThousandChars":
                self = .perThousandChars(rate: try c.decode(Double.self, forKey: .rate))
            case "perSecond":
                self = .perSecond(
                    rate: try c.decode(Double.self, forKey: .rate),
                    textRate: try c.decodeIfPresent(Double.self, forKey: .textRate)
                )
            case "flat":
                self = .flat(price: try c.decode(Double.self, forKey: .price))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .mode, in: c,
                    debugDescription: "Unknown audio pricing mode"
                )
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, displayName, providerIconKey, providerName, description, allowedEndpoints, responseShape, uiCapabilities
        case creditsPerSecond, audioDiscountRate, creditsPerImage, qualities
        case audioPricing, creditsPerSecondUpscale, upscalePricing, paidOnly
    }

    /// Defining `init(from:)` suppresses the memberwise init, and the catalog is now also
    /// built in code from `/api/v1/pricing`, so spell it out.
    init(
        id: String,
        kind: Kind,
        displayName: String,
        providerIconKey: String? = nil,
        providerName: String? = nil,
        description: String? = nil,
        allowedEndpoints: [String] = [],
        responseShape: ResponseShape,
        uiCapabilities: UICapabilities,
        creditsPerSecond: [String: Double]? = nil,
        audioDiscountRate: [String: Double]? = nil,
        creditsPerImage: [String: Double]? = nil,
        qualities: [String]? = nil,
        audioPricing: AudioPricing? = nil,
        creditsPerSecondUpscale: Double? = nil,
        upscalePricing: UpscalePricing? = nil,
        paidOnly: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.providerIconKey = providerIconKey
        self.providerName = providerName
        self.description = description
        self.allowedEndpoints = allowedEndpoints
        self.responseShape = responseShape
        self.uiCapabilities = uiCapabilities
        self.creditsPerSecond = creditsPerSecond
        self.audioDiscountRate = audioDiscountRate
        self.creditsPerImage = creditsPerImage
        self.qualities = qualities
        self.audioPricing = audioPricing
        self.creditsPerSecondUpscale = creditsPerSecondUpscale
        self.upscalePricing = upscalePricing
        self.paidOnly = paidOnly
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.kind = try c.decode(Kind.self, forKey: .kind)
        self.displayName = try c.decode(String.self, forKey: .displayName)
        self.providerIconKey = try c.decodeIfPresent(String.self, forKey: .providerIconKey)
        self.providerName = try c.decodeIfPresent(String.self, forKey: .providerName)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.allowedEndpoints = try c.decode([String].self, forKey: .allowedEndpoints)
        self.responseShape = try c.decode(ResponseShape.self, forKey: .responseShape)
        self.creditsPerSecond = try c.decodeIfPresent([String: Double].self, forKey: .creditsPerSecond)
        self.audioDiscountRate = try c.decodeIfPresent([String: Double].self, forKey: .audioDiscountRate)
        self.creditsPerImage = try c.decodeIfPresent([String: Double].self, forKey: .creditsPerImage)
        self.qualities = try c.decodeIfPresent([String].self, forKey: .qualities)
        self.audioPricing = try c.decodeIfPresent(AudioPricing.self, forKey: .audioPricing)
        self.creditsPerSecondUpscale = try c.decodeIfPresent(Double.self, forKey: .creditsPerSecondUpscale)
        self.upscalePricing = try c.decodeIfPresent(UpscalePricing.self, forKey: .upscalePricing)
        self.paidOnly = try c.decodeIfPresent(Bool.self, forKey: .paidOnly) ?? false
        switch self.kind {
        case .video:
            self.uiCapabilities = .video(try c.decode(VideoCaps.self, forKey: .uiCapabilities))
        case .image:
            self.uiCapabilities = .image(try c.decode(ImageCaps.self, forKey: .uiCapabilities))
        case .audio:
            self.uiCapabilities = .audio(try c.decode(AudioCaps.self, forKey: .uiCapabilities))
        case .upscale:
            self.uiCapabilities = .upscale(try c.decode(UpscaleCaps.self, forKey: .uiCapabilities))
        }
    }
}

struct VideoCaps: Decodable, Sendable {
    let supportsPrompt: Bool?
    let durations: [Int]
    let resolutions: [String]?
    let aspectRatios: [String]
    let supportsFirstFrame: Bool
    let supportsLastFrame: Bool
    let maxReferenceImages: Int
    let maxReferenceVideos: Int
    let maxReferenceAudios: Int
    let maxTotalReferences: Int?
    let maxCombinedVideoRefSeconds: Double?
    let maxCombinedAudioRefSeconds: Double?
    let framesAndReferencesExclusive: Bool
    let referenceTagNoun: String
    let requiresSourceVideo: Bool
    let maxSourceVideoSeconds: Double?
    let maxSourceVideoResolution: SourceVideoResolution?
    let requiredSourceVideoEncoding: SourceVideoEncoding?
    let requiresReferenceImage: Bool
    let requiresReferenceAudio: Bool?
    let draftCreditsPerSecond: Double?
    let draftEnhanceCreditsPerSecond: Double?
    let sourceVideoCreditsPerSecond: [String: Double]?
    let sourceVideoDraftCreditsPerSecond: Double?
}

enum SourceVideoResolution: String, Decodable, Sendable {
    case p720 = "720p", p1080 = "1080p", p4k = "4k"
}

enum SourceVideoEncoding: String, Decodable, Sendable {
    case h264MP4 = "h264-mp4"
}

struct ImageCaps: Decodable, Sendable {
    let resolutions: [String]?
    let aspectRatios: [String]
    let qualities: [String]?
    let supportsImageReference: Bool
    let maxImages: Int
}

struct AudioCaps: Decodable, Sendable {
    let category: String
    let voices: [String]?
    let defaultVoice: String?
    let supportsLyrics: Bool
    let supportsInstrumental: Bool
    let supportsStyleInstructions: Bool
    let durations: [Int]?
    let durationRange: AudioDurationRange?
    let minPromptLength: Int
    let maxReferenceImages: Int?
    let maxReferenceAudios: Int?
    let maxReferenceAudioSeconds: Double?
    let referenceAudioExtensions: [String]?
    let referenceImagesAndAudiosExclusive: Bool?
    let supportsMultilingual: Bool?
    let inputs: [String]?
    let promptLabel: String?
    let minSeconds: Int?
    let maxSeconds: Int?
    let targetLanguages: [String]?
    let defaultTargetLanguage: String?
}

struct AudioDurationRange: Decodable, Sendable {
    let minimum: Int
    let maximum: Int
    let defaultValue: Int
}

struct UpscaleCaps: Decodable, Sendable {
    let speed: String   // "Fast" | "Medium" | "Slow"
    let p75DurationSeconds: Int
    let maximumUpscaleFactor: Double?
    let supportedTypes: [String]   // "video" | "image"
    let selectSettings: [UpscaleSelectSetting]?
    let numericSettings: [UpscaleNumericSetting]?
    let toggleSettings: [UpscaleToggleSetting]?
}
