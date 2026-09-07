import Foundation
import Testing
@testable import PalmierPro

/// **首帧那条快车道** —— 网关那条 WS，Mac 此前一行都没接。
///
/// ## 为什么现在接
///
/// 2026-09-06 的数：做好的 404 条草案里只有 52 条（12.9%）的主人
/// 撑到了第一张画面就绪的时刻（合伙人掐表：17.1 秒），
/// 而 45/63 的人在第 10 秒就不动了。**那 17 秒里唯一真的救场的动作是"下图"**，
/// 而走轮询的话，首帧名字要等下一次轮询撞上，每次还要多花一整个往返。
///
/// ⚠ **说准这条改动省的是什么**：省的是那一次 REST 往返（国内实测 1.0–1.5 秒）
/// 和轮询的间隔量化。**它不省模型的时间，也不改 17.1 秒那个数。**
/// Mac 那段老注释说的"白丢 2.6 秒"是**四秒轮询那个年代的数**，
/// 而轮询早就在没首帧时收紧到 1.2 秒了 —— 拿那句注释当理由是拿一个过期的数做决定。
///
/// ## 这一条守的两件事
///
/// 一是**安全**：WS 带不了 header，凭证只能进 query，而 query 会进访问日志。
/// 网关为此把 `?token=`（七天 JWT）整条拆掉，只认五分钟一次性的票据。
/// **客户端这侧要有一条判据钉住"我们不会把 JWT 放进去"** ——
/// 网关那侧拒了会 401，而 401 之后我们有轮询兜底，
/// **于是这个错误会变成一个安静的空操作**（网关注释里记着他们自己栽过同款）。
///
/// 二是**报文**：字段名是网关 `push_progress` 里那个 `json!` 的字面量。
/// 少一个下划线，`first_frames` 解不出来，快车道就永远不下图 ——
/// 而屏幕上照样有轮询兜底，**没有任何东西会红**。
@Suite("首帧快车道")
struct ProgressStreamTests {

    // MARK: - 地址

    @Test func theSocketURLCarriesOnlyTheTicket() throws {
        let url = MetagGateway.progressURL(job: "abc-123", ticket: "T-999")
        let comps = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(comps.scheme == "wss" || comps.scheme == "ws", "没有升级成 ws：\(url)")
        #expect(url.path.hasSuffix("/ws/abc-123"), "路径不对：\(url.path)")
        let names = (comps.queryItems ?? []).map(\.name)
        #expect(names == ["ticket"],
                "query 里除了票据还有别的东西：\(names) —— query 会进访问日志")
    }

    /// **JWT 不许出现在这个 URL 的任何地方。**
    /// 网关拒了会 401，而我们有轮询兜底 —— 所以这个错误不会有任何症状。
    @Test func theSocketURLNeverCarriesTheJWT() {
        let fakeJWT = "eyJhbGciOiJIUzI1NiJ9.PRETEND.SIGNATURE"
        let url = MetagGateway.progressURL(job: "j", ticket: "T").absoluteString
        #expect(!url.contains(fakeJWT))
        #expect(!url.contains("token="), "URL 里出现了 token= —— 网关已经把这条路拆了：\(url)")
    }

    // MARK: - 报文

    /// 网关 `push_progress` 里 `json!` 的字面量，一字未改。
    /// **`peek.merge_into` 补的那几个键（first_frames / storyboard_preview /
    /// first_frame_at_ms / frames_done / hook_line）也在。**
    private static let live = """
    {"status":"running","position":0,"estimated_wait":"约 1 分钟","eta_secs":58,
     "shots_done":0,"shots_total":4,"stage":"storyboard",
     "frames_done":1,"storyboard_preview":["天台上，城市的灯一格一格亮起来"],
     "first_frames":["shot0_first.jpg"],"hook_line":null,
     "first_frame_at_ms":1757155200000}
    """

    private static func decode(_ s: String) throws -> MetagGateway.Progress {
        try JSONDecoder().decode(MetagGateway.Progress.self, from: Data(s.utf8))
    }

    /// **这一条就是快车道的全部理由**：首帧的名字真的解得出来。
    ///
    /// ⚠ 说准它守得住什么：把 Swift 那个属性改名，**编译器会先拦住**
    /// （调用点在 `MetagDraftSheet`），所以这一条不是那个方向的守卫。
    /// 它守的是**加一个 CodingKeys 把键名映歪**这一类。
    /// **网关那侧改了键名，客户端没有任何判据拦得住** —— 那只能靠
    /// 网关自己的判据，或者靠这份夹具哪天对不上真报文。这是已知的缺口，
    /// 不假装它不存在。
    @Test func theFirstFrameNamesAreActuallyDecoded() throws {
        let p = try Self.decode(Self.live)
        #expect(p.first_frames == ["shot0_first.jpg"],
                "first_frames 没解出来 —— 快车道会永远不下图，而轮询兜底让它没有症状")
        #expect(p.first_frame_at_ms == 1757155200000, "就绪时刻没解出来，首帧延迟会量不到")
    }

    /// 其余字段也得解得出来 —— 少一个不会报错，只会静默丢掉。
    @Test func theRestOfTheContractDecodes() throws {
        let p = try Self.decode(Self.live)
        #expect(p.stage == "storyboard")
        #expect(p.shots_total == 4)
        #expect(p.eta_secs == 58)
        #expect(p.storyboard_preview?.count == 1)
    }

    /// 终结态要认得出来，否则那条流会一直挂着不收。
    @Test func terminalStatesEndTheStream() throws {
        #expect(try Self.decode(#"{"status":"done"}"#).isTerminal)
        #expect(try Self.decode(#"{"status":"failed"}"#).isTerminal)
        #expect(try Self.decode(#"{"status":"running"}"#).isTerminal == false)
    }

    /// **老网关少发几个字段时不许整条解不出来。**
    /// 解不出来那一条会被丢掉，而丢掉的是首帧 —— 快车道当场退化成没接。
    @Test func aSparsePayloadStillDecodes() throws {
        let p = try Self.decode(#"{"status":"running","position":2}"#)
        #expect(p.first_frames == nil)
        #expect(p.isTerminal == false)
    }
}

/// **两条路送同一份分镜，屏幕上的规则只有一条。**
///
/// 轮询在拿到首帧之后退回 4 秒一轮，而分镜正是在那段一句句往外冒的；
/// WS 每 2 秒推一次同样的 `storyboard_preview`。合伙人 2026-09-06 把第一句
/// 从 13.5 秒提到 6.55 秒之后，**这几秒正落在那 45 个人离开的窗口里**。
///
/// ⚠ 两个来源写同一块屏，是这个仓明令要小心的形状。所以规则钉死在一处：
/// 落定的 `shots` 最大，否则**谁的句子多听谁的** —— 不按"谁更新"，
/// 那要再存一个时间戳，而两条路各自的时钟不一定同步。
@Suite("分镜的两条路")
@MainActor
struct StreamedNarrationTests {

    @Test func theStreamedLinesShowUpWhenPollingHasNothingYet() {
        let m = MetagDraftModel()
        m.applyStreamed(["第一句"])
        #expect(m.narrations == ["第一句"], "WS 送来的句子没上屏")
    }

    /// **只增不减。** 网关推的是当下快照，Redis 抖一下可能回一份更短的 ——
    /// 那会让屏幕上已经出现的句子当着他的面消失。
    @Test func aShorterSnapshotNeverErasesWhatHeAlreadySaw() {
        let m = MetagDraftModel()
        m.applyStreamed(["一", "二", "三"])
        m.applyStreamed(["一"])
        #expect(m.narrations.count == 3, "更短的一份把屏幕上的句子擦掉了")
        m.applyStreamed(nil)
        #expect(m.narrations.count == 3, "nil 把屏幕擦掉了")
    }

    /// 落定的分镜最大 —— 那是这条片子最终的那一份。
    @Test func theSettledStoryboardWins() throws {
        let m = MetagDraftModel()
        m.applyStreamed(["草稿一", "草稿二", "草稿三"])
        m.applyJobForTesting(try JSONDecoder().decode(
            MetagGateway.Job.self,
            from: Data(#"{"job_id":"j","shots":[{"narration":"定稿","video":"v","audio":"a"}]}"#.utf8)))
        #expect(m.narrations == ["定稿"], "落定之后还在显示草稿")
    }
}
