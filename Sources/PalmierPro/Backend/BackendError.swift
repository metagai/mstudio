import Foundation

enum BackendError: LocalizedError {
    case notConfigured
    /// METAG 网关暂不支持的生成类型（音频/图片/放大）—— 明确报错而不是静默走视频
    case unsupported
    case transport(String)
    case api(status: Int, code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "METAG 账号未配置或未登录。"
        case .unsupported: "该生成类型暂未开放（当前支持文生视频与图生视频）。"
        case .transport(let message): message
        case .api(_, _, let message): message
        }
    }
}
