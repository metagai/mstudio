struct CaptionGapSettings: Equatable, Sendable {
    static let maximumGapRange = 0.0...2.0
    /// 0.5 秒：这个阈值同时是最后一条字幕的按住时长（上游 5ddc2fa 一起调的），
    /// 0.25 秒按不住一条一闪而过的收尾字幕。
    static let `default` = CaptionGapSettings(uncheckedMaximumGapSeconds: 0.5)

    let maximumGapSeconds: Double

    init?(maximumGapSeconds: Double) {
        guard maximumGapSeconds.isFinite,
              Self.maximumGapRange.contains(maximumGapSeconds) else { return nil }
        self.init(uncheckedMaximumGapSeconds: maximumGapSeconds)
    }

    func maximumGapFrames(fps: Int) -> Int {
        guard fps > 0, maximumGapSeconds > 0 else { return 0 }
        let frames = (maximumGapSeconds * Double(fps)).rounded(.down)
        guard frames.isFinite else { return 0 }
        return frames >= Double(Int.max) ? Int.max : Int(frames)
    }

    private init(uncheckedMaximumGapSeconds: Double) {
        self.maximumGapSeconds = uncheckedMaximumGapSeconds
    }
}
