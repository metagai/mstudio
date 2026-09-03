import Foundation

/// 首屏那几条**真片子**。
///
/// ## 之前发生的事
///
/// 首屏是纯文字：一句承诺（「写一句话，METAG 分镜、配音、配乐，再把它剪成片子」）
/// 加三行写死的英文例句。**一个视频产品，第一屏一帧画面都没有。**
/// 他凭什么相信这句承诺？
///
/// 而线上 `metag.ai/media/showcase.json` 里**早就躺着 12 条完整样片** ——
/// 海报、mp4、三语文案、每一镜的清单，落地页在用，Mac 端一条都没接。
/// 又一台做好了没接线的机器，而且是最贵的那一台：
/// **我们有片子，而他看不到。**
///
/// ## 样片就是样片
///
/// 不把它包装成「你也能一键做出这个」。这几条是精修过的，
/// 他照着拍未必是这个效果 —— 那种承诺兑现不了的时候，比不承诺更伤。
/// 它在这里只做一件事：**让他相信这东西真能出片。**
struct MetagShowcase: Sendable, Identifiable, Equatable {
    let id: String
    /// 一句话说清这条片子讲什么（跟界面语言）。
    let line: String
    let poster: URL
    let reel: URL
    /// 竖片横片混着，格子按各自比例排 —— 一刀切成 16:9 会把竖片裁掉半张脸。
    let aspect: Double

    /// 首屏放几条。**不是越多越好**：这一屏的主角是那个输入框。
    static let firstScreenCount = 3

    /// 站点根。跟**界面语言**走，不跟服务端 region 走 ——
    /// 后者在国内网关重启时会被 nginx 静默兜到海外（`Updater.downloadPage` 同款）。
    nonisolated static func siteRoot(language: String) -> URL {
        language == "zh"
            ? URL(string: "https://metag-ai.com")!
            : URL(string: "https://metag.ai")!
    }

    @MainActor
    static var siteRoot: URL { siteRoot(language: AppLocalization.shared.gatewayLanguage) }

    /// 一条 JSON 记录 → 一条样片。**缺哪一样就整条不要**，
    /// 不摆一个点了播不出来的格子。
    nonisolated static func parse(_ raw: [String: Any], language: String, root: URL) -> MetagShowcase? {
        guard let id = raw["id"] as? String,
              let posterPath = raw["poster"] as? String,
              let reelPath = raw["reel"] as? String,
              let poster = URL(string: posterPath, relativeTo: root)?.absoluteURL,
              let reel = URL(string: reelPath, relativeTo: root)?.absoluteURL
        else { return nil }
        return MetagShowcase(
            id: id,
            line: localized(raw["lines"], language: language) ?? id,
            poster: poster,
            reel: reel,
            aspect: aspect(from: raw["recipe"])
        )
    }

    /// `{"zh": …, "en": …, "es": …}` → 这台机器上该显示的那一句。
    /// 没有对应语言就退回英文 —— **退回英文好过留空**。
    nonisolated static func localized(_ value: Any?, language: String) -> String? {
        guard let map = value as? [String: Any] else { return value as? String }
        for key in [language, "en"] {
            if let s = map[key] as? String, !s.isEmpty { return s }
        }
        return nil
    }

    /// `recipe.resolution` 长得像 `1280×720`、`720×1280`，也可能是 `720P`。
    /// **读不出来就当横的** —— 那是这批样片里的多数，猜错了格子只是略扁。
    nonisolated static func aspect(from recipe: Any?) -> Double {
        guard let recipe = recipe as? [String: Any],
              let resolution = recipe["resolution"] as? String else { return 16.0 / 9 }
        let parts = resolution.split(whereSeparator: { "×x*".contains($0) })
        guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]), h > 0
        else { return 16.0 / 9 }
        return w / h
    }

    /// 整份清单 → 首屏那几条。
    nonisolated static func firstScreen(
        _ data: Data, language: String, root: URL, count: Int = firstScreenCount
    ) -> [MetagShowcase] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return list.compactMap { parse($0, language: language, root: root) }.prefix(count).map { $0 }
    }
}
