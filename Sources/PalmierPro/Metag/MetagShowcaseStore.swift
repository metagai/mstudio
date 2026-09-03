import Foundation

/// 首屏那几条片子从哪来。
///
/// **取不到就当没有。** 首屏回退到原来那三行例句 —— 一个视频产品的第一屏
/// 可以少几张海报，但不能是一片空白（`docs/lessons.md` 第三十七条：
/// 把"不知道"画成事实，最坏的一种是界面元素无声消失）。
@MainActor
@Observable
final class MetagShowcaseStore {
    static let shared = MetagShowcaseStore()

    private(set) var films: [MetagShowcase] = []
    @ObservationIgnored private var started = false

    private init() {}

    /// 取一次就够。首屏每次重绘都拉一遍的话，一屏十次网络请求。
    func loadOnce() {
        guard !started else { return }
        started = true
        Task { [weak self] in
            guard let self else { return }
            let root = MetagShowcase.siteRoot
            let language = AppLocalization.shared.gatewayLanguage
            let url = root.appendingPathComponent("media/showcase.json")
            var request = URLRequest(url: url)
            // 首屏不等它 —— 超过这个数就当没有，别让一排海报把那句话拖住。
            request.timeoutInterval = 8
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200
            else { return }
            films = MetagShowcase.firstScreen(data, language: language, root: root)
        }
    }
}
