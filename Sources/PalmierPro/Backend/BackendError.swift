import Foundation

enum BackendError: LocalizedError {
    case notConfigured
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
        case .notConfigured: "METAG 账号未配置或未登录。"
        case .unsupported: "该生成类型暂未开放（当前支持文生视频与图生视频）。"
        case .transport(let message): message
        case .api(_, _, let message): message
        case .imageNotSupported(let engine):
            "\(engine) 不支持自带图片，它只按文字生成。要用这张图，请选「标准（自研）」或 Grok。"
        }
    }
}
