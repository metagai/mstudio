import Foundation
import Testing
@testable import PalmierPro

/// 每一次网关调用都自报家门。
///
/// ## 之前发生的事
///
/// 2026-09-05：`jobs` 表**没有任何一列记来源**，于是"这条草案是谁起的"
/// 只能靠猜提示词内容。那天我和 partner 各自拿出一套"证据"，**两套都是恒真的**
/// （他那条被限流闸决定：每个匿名身份 24 小时只能起一条；
/// 我那条被代码路径决定：票是起草案前一刻才领的）。最后谁也证不了谁 ——
/// **缺的不是推理，是裁判。**
///
/// 这一条守的是客户端这一半：**每一个网关请求都带得出 `X-Metag-Client`。**
@Suite("网关调用要自报家门")
struct ClientTagTests {

    @Test func everyGatewayRequestCarriesTheClientTag() {
        let req = MetagGateway.urlRequest("api/v1/anything")
        #expect(req.value(forHTTPHeaderField: "X-Metag-Client") == MetagGateway.clientTag)
    }

    /// 网关那侧要按它分流量，**值的形状不能随手改**：`mac/<版本>`。
    @Test func theTagNamesTheClientAndItsVersion() {
        let tag = MetagGateway.clientTag
        #expect(tag.hasPrefix("mac/"), "网关按前缀分客户端，`mac/` 不能丢：\(tag)")
        #expect(tag.count > 4, "版本号读不出来也要有个值，不能只剩 `mac/`")
        #expect(!tag.contains(" "), "头的值里不许有空格：\(tag)")
    }

    /// 路径拼接不能被这个头改坏 —— 它只加头，不动 URL。
    @Test func theFactoryStillBuildsTheRightURL() {
        let req = MetagGateway.urlRequest("api/v1/quote")
        #expect(req.url?.path.hasSuffix("/api/v1/quote") == true, "URL 被改坏了：\(req.url as Any)")
    }
}
