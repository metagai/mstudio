import Foundation

enum BackendError: LocalizedError {
    case notConfigured
    /// **参考图要把他的素材传上云，而我们承诺素材不出这台电脑。**
    ///
    /// 这原来复用 `.notConfigured`，于是屏幕上写的是「你没登录 METAG」——
    /// 一个**产品决定**被报成了**他的错误**，而他明明已经登录。
    /// 他会一遍遍去重新登录，永远也不会成功。
    ///
    /// 说清楚之后它甚至不是坏消息：那是我们守住的一条线。
    case referencesStayLocal
    /// METAG 网关暂不支持的生成类型（音频/图片/放大）—— 明确报错而不是静默走视频
    case unsupported
    case transport(String)
    case api(status: Int, code: String, message: String)
    /// 选的档吃不下用户给的图。**必须在扣费之前说清楚** ——
    /// seedance / veo / cloud 的提交体里只有 prompt，图会被静默丢弃，
    /// 而按 26~60 credits/镜已经付过了。一个 HTTP 400 解释不了这件事。
    case imageNotSupported(engine: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: L10n.key("Not signed in to METAG.")
        case .referencesStayLocal:
            L10n.key("Reference footage would have to leave this Mac, and METAG doesn't upload your footage. Text and a first frame both work.")
        case .unsupported: L10n.key("That generation type is not available yet — text-to-video and image-to-video are.")
        case .transport(let message): message
        case .api(_, _, let message): message
        case .imageNotSupported(let engine):
            // **不要在这里点名哪几档收图。** 上一版写的是「标准（自研）」或 Grok ——
            // 后来 grok 停售、wan-flash 上架，这句话就开始把用户指向买不到的档。
            // 收不收图是报价单的 `accepts_image`，选择器已经据此禁用了不收图的档。
            "\(engine): " + L10n.key("generates from text only and ignores an attached image — pick a tier that takes a reference image.")
        }
    }
}
