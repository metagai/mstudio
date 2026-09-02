import Foundation
import Testing
@testable import PalmierPro

/// **他等了九十秒、付了 credits，拿到的是素材库里 N 个散文件和一条空时间线。**
///
/// `addMediaAsset` 只把素材加进库，从来不铺时间线；而片子落地这条路只调它。
/// 这个产品的承诺是"一句话变成一条片子"，交付的是一堆配料 ——
/// 他得自己把每一镜拖进去、排好序、再把旁白一条条对齐到各自那一镜。
///
/// 网关那侧早就为此准备好了 `shot_clips`：
/// 「一条压平的片子在时间线上只有一个色块……有了这份清单，
/// 编辑器铺的是 N 段可编辑素材。」
@Suite("片子铺到时间线上")
struct MetagFilmLayoutTests {
    /// 网关给的逐段时长是权威的 —— 30fps 下 2 秒就是 60 帧。
    @Test func startsComeFromTheGatewaysDurations() {
        let starts = MetagFilmLayout.startSeconds(
            shotCount: 3, clipSeconds: [2.0, 1.0, 3.0],
            measured: { _ in Issue.record("有权威时长还去量文件"); return 1 }
        )
        #expect(starts == [0, 2, 3])
    }

    /// **拿不到就自己量，不要凭空假设等长。**
    @Test func withoutDurationsItMeasures() {
        let starts = MetagFilmLayout.startSeconds(
            shotCount: 3, clipSeconds: nil, measured: { _ in 1.5 }
        )
        #expect(starts == [0, 1.5, 3])
    }

    /// 清单比镜头短、或者某一段是 0 —— 那几段退回实测，**不整条作废**。
    @Test func aShortOrBrokenListFallsBackPerShot() {
        let starts = MetagFilmLayout.startSeconds(
            shotCount: 3, clipSeconds: [2.0, 0], measured: { _ in 0.5 }
        )
        #expect(starts == [0, 2, 2.5])
    }

    /// 一镜也是对的；零镜不该崩。
    @Test(arguments: [(0, [Double]()), (1, [0.0])])
    func edgesHold(count: Int, expected: [Double]) {
        #expect(MetagFilmLayout.startSeconds(
            shotCount: count, clipSeconds: nil, measured: { _ in 1 }
        ) == expected)
    }

    /// **旁白落在各自那一镜的起点。**
    ///
    /// 这一条问的是那个判断本身。**上一版问的是源码里那行字还在不在** ——
    /// 而把 `fps` 传成 0（两个源码字符串一字不改），每一段旁白都落到开头，
    /// 正是 web 端那次「多个音轨叠加」，而判据全绿。
    @Test func eachNarrationLandsOnItsOwnShot() {
        // 三镜，第二镜原生出声（没有旁白）。**按镜号配，不按位置配。**
        let placed = MetagFilmLayout.narrationFrames(
            shots: [0, 1, 2], narrations: [0, 2], starts: [0, 60, 90])
        #expect(placed.map(\.shot) == [0, 2], "把旁白配到了没有旁白的那一镜上")
        #expect(placed.map(\.frame) == [0, 90],
                "第三镜的旁白落在 \(placed.map(\.frame)) —— 它该落在自己那一镜的起点")
    }

    /// **不许全叠在开头。**
    @Test func narrationsNeverAllStackAtTheStart() {
        let starts = MetagFilmLayout.startSeconds(
            shotCount: 3, clipSeconds: [2, 2, 2], measured: { _ in 1 }).map { Int($0 * 30) }
        let placed = MetagFilmLayout.narrationFrames(
            shots: [0, 1, 2], narrations: [0, 1, 2], starts: starts)
        #expect(Set(placed.map(\.frame)).count == 3,
                "三段旁白落在 \(placed.map(\.frame)) —— 叠在一起了")
    }

    /// **那个能传错的参数已经不存在了。**
    ///
    /// 上一版 `startFrames` 收一个 `fps`；把它传成 0（源码字符串一字不改），
    /// 每一段旁白都落到开头 —— 正是 web 端那次「多个音轨叠加」——
    /// 而判据全绿。给它加下限只是把 [0,1,2] 变成 [0,2,4]，还是塌的。
    ///
    /// **判据看不见的错，就让它写不出来**：起点按秒算，
    /// 换算交给 `EditorViewModel.frame(atSeconds:)`，fps 从时间线自己读。
    @Test @MainActor func thereIsNoFpsToGetWrong() {
        let editor = EditorViewModel()
        editor.timeline = Fixtures.timeline(tracks: [])
        // 时间线自己的 fps 被弄坏时也不塌成一堆 —— 换算那一处兜了下限。
        editor.timeline.fps = 0
        let seconds = MetagFilmLayout.startSeconds(
            shotCount: 3, clipSeconds: [2, 2, 2], measured: { _ in 1 })
        let frames = seconds.map(editor.frame(atSeconds:))
        #expect(Set(frames).count == 3, "起点算出来是 \(frames) —— 三镜叠在一起了")
    }

    /// **网关不给时长的时候，实测那一路必须真的量得出东西。**
    ///
    /// 2026-09-02 产品技术负责人查出：`shot_clips` 只活在 Redis 里，
    /// 24 小时后走 PG 归档路，那条路上没有这个字段 ——
    /// **也就是每一部第二天打开的片子**。
    ///
    /// 而 Mac 这侧的"退回实测"当时是假的：`addMediaAsset` 立刻返回，
    /// `asset.duration` 是后台 Task 补的，铺片子那一刻还是 0 ——
    /// 退回实测等于退回 0，十一镜全叠在一起相距一帧。
    ///
    /// 现在时长在下载完那一刻现量。这一条盯着：**量不到就不该铺出一堆重叠。**
    @Test func withoutGatewayDurationsTheShotsStillSeparate() {
        let starts = MetagFilmLayout.startSeconds(
            shotCount: 4, clipSeconds: nil, measured: { _ in 5.0 })
        #expect(starts == [0, 5, 10, 15], "网关不给时长时铺成了 \(starts)")
        #expect(Set(starts).count == 4)
    }

    /// **量不到的那一镜，拿量得到的那些顶上。**
    ///
    /// 上一版这条断言的是"四个起点互不相同" —— 而下限是 0.04 秒，
    /// 30fps 下那是第 0/1/2/4 帧，**判据绿而用户看到的仍然是全叠在一起**。
    /// 产品技术负责人那一问：「它绿的时候，用户拿到的是完整的，还是只是拿到了？」
    ///
    /// 所以现在断言的是**真的分得开**（每镜至少一秒），不是"数值不相等"。
    @Test func anUnmeasurableShotBorrowsFromTheOthers() {
        // **各镜长度要不一样** —— 都一样的话，最小值和中位数是同一个数，
        // 这条判据就分不出"拿中位数顶"和"拿最短的那一镜顶"。
        // （第一次写的夹具就是三镜都 5 秒，变异 B 因此红不起来 ——
        // 夹具分不出来，判据就没在守那个选择。）
        let lengths = [3.0, 0, 5.0, 9.0]        // 第二镜读不出
        let starts = MetagFilmLayout.startSeconds(
            shotCount: 4, clipSeconds: nil, measured: { lengths[$0] })
        // 顶上来的是中位数 5，不是最短的 3：**一镜坏掉不该把整片压扁**。
        #expect(starts == [0, 3, 8, 13], "读不出的那一镜顶错了长度：\(starts)")
    }

    /// 一镜都量不到（每个文件都读不出）也不许塌成一堆。
    @Test func evenAZeroMeasurementDoesNotStackThem() {
        let starts = MetagFilmLayout.startSeconds(
            shotCount: 4, clipSeconds: nil, measured: { _ in 0 })
        let gaps = zip(starts.dropFirst(), starts).map(-)
        #expect(gaps.allSatisfy { $0 >= 1 },
                "起点是 \(starts) —— 数值不相等，但 30fps 下还是叠在一起")
    }

    /// **只剩这一条比源码：整件事是一步撤销。**
    ///
    /// 它是一个结构事实，不是能算出来的值 —— 没有别的问法。
    ///
    /// 上一版这里还有两条（"调用点有没有算旁白落点""有没有补主音量"），
    /// 而它们在我把那几个决定收成一份 `Plan` 之后**当场红了** ——
    /// 咬的是函数名，代码变好它就报警。那两件事现在由
    /// `OpenFinishedFilmTests` 直接问那份铺法，比问名字结实。
    @Test func theWholeFilmIsOneUndoStep() throws {
        let src = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/PalmierPro/Metag/MetagJobOpener.swift"),
            encoding: .utf8)
        #expect(src.contains("editor.undo.perform(L10n.string(\"Add Film\"))"),
                "铺片子变成好几步撤销了 —— 他做的是「打开一条片子」这一个动作")
    }
}
