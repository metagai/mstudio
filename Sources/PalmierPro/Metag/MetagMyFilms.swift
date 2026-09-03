import SwiftUI

/// 我的作品。
///
/// 这个入口此前不存在 —— 用户只能靠自己还留着的深链打开某一单，
/// 关掉窗口就再也找不回来，而 credits 已经扣了。
///
/// 真实事故（2026-08-01，web 端新用户）：产物只在服务端内存盘留六十分钟、
/// 任务元数据留二十四小时，中间那二十三小时任务一直"声称 done"而文件早没了 ——
/// 他回来看到"全部生成失败"，四个 credits 花得不明不白。
/// 交付物已经改为落对象存储，而"看得见自己买过什么"是这件事的另一半：
/// **存得住却找不到，和没存住没有区别。**
@MainActor
final class MetagMyFilmsModel: ObservableObject {
    /// 已经有货的模型：**给取景器和 Xcode 预览用**。
    ///
    /// 这一屏此前只被看过「正在载入」那一版 —— 而空屋子里藏不住东西。
    /// 有货那一版的问题（行怎么排、缩略图什么时候到、长 prompt 会不会把行撑爆）
    /// 只有真喂了数据才看得见。
    ///
    /// `load()` 见到 `seeded` 就不再去网络，否则一喂进来就被一个失败的请求盖掉。
    convenience init(preloaded: [MetagGateway.FilmRow]) {
        self.init()
        films = preloaded
        seeded = true
    }

    private var seeded = false
    @Published private(set) var films: [MetagGateway.FilmRow] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    /// 正在删的那一条（或 "__all__" 表示批量清理）。**删除期间要禁用按钮** ——
    /// 连点两次会对同一条发两次 DELETE，第二次拿 404，看起来像出错了。
    @Published private(set) var busy: String?
    /// 刚复制到剪贴板的那条链接 —— 让他看得见"确实拿到了"。
    @Published private(set) var shared: String?

    var failedCount: Int { films.filter { $0.status == "failed" }.count }

    /// 删一条。**乐观移除**：服务端已经删掉了，再拉一次列表只是让用户多等一轮。
    /// 换一条公开链接并放进剪贴板。分享的下一步一定是粘进某个聊天框。
    func share(_ id: String) async {
        busy = id
        defer { busy = nil }
        do {
            let url = try await MetagGateway.shareFilm(id)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url, forType: .string)
            MetagFunnel.track(.shared)
            shared = url
        } catch {
            self.error = error.localizedDescription
        }
    }

    func remove(_ id: String) async {
        busy = id
        defer { busy = nil }
        do {
            try await MetagGateway.deleteFilm(id)
            films.removeAll { $0.job_id == id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 一键清空失败的。**一条条点是在让用户重复面对失败** ——
    /// 而失败记录恰恰是他最想让它消失的东西。
    /// 单条失败不拦住其余：删不掉一条不该让整次清理停下。
    func clearFailed() async {
        busy = "__all__"
        defer { busy = nil }
        for f in films where f.status == "failed" {
            if (try? await MetagGateway.deleteFilm(f.job_id)) != nil {
                films.removeAll { $0.job_id == f.job_id }
            }
        }
    }

    func load() async {
        guard !seeded else { return }
        loading = true
        defer { loading = false }
        do {
            films = try await MetagGateway.myFilms()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct MetagMyFilmsView: View {
    @StateObject private var model: MetagMyFilmsModel

    init(onOpen: @escaping (MetagGateway.FilmRow) -> Void,
         model: MetagMyFilmsModel = MetagMyFilmsModel()) {
        self.onOpen = onOpen
        _model = StateObject(wrappedValue: model)
    }
    /// 点开一部作品要做什么，由调用方决定 —— 这个视图只负责"看得见、点得到"。
    var onOpen: (MetagGateway.FilmRow) -> Void

    @State private var posters = MetagPosterCache.shared

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Text(L10n.string("My films")).font(.system(size: AppTheme.FontSize.mdLg, weight: AppTheme.FontWeight.semibold))
                Spacer()
                if model.failedCount > 0 {
                    Button(model.busy == "__all__"
                           ? L10n.key("Clearing…")
                           : L10n.string("Clear \(model.failedCount.formatted()) failed")) {
                        Task { await model.clearFailed() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Status.warningColor)
                    .disabled(model.busy != nil)
                }
            }
            // 复制完了要看得见 —— 剪贴板是没有反馈的，静悄悄等于"没反应"。
            if let u = model.shared {
                Text(L10n.string("Link copied") + " · " + u)
                    .foregroundStyle(AppTheme.Text.secondaryColor).font(.system(size: AppTheme.FontSize.sm)).textSelection(.enabled)
            }
            // **一次分享失败，不该让他的作品全部消失。**
            //
            // 原来 `error` 这一支排在 `films` 前面：列表已经加载好之后，
            // 点分享或删除失败会把 `model.error` 置上，于是整屏作品被一行灰字顶掉 ——
            // 他看到的是"我的东西全没了"，而它们好好地在服务器上。
            //
            // 分成两种：**取不到列表**（那时确实只有一句话可说）和
            // **列表在、这一次操作失败**（那句话该贴在列表上方，不是取代列表）。
            if model.loading && model.films.isEmpty {
                Text(L10n.string("Loading…")).foregroundStyle(AppTheme.Text.secondaryColor).font(.system(size: AppTheme.FontSize.sm))
            } else if let e = model.error, model.films.isEmpty {
                Text(e).foregroundStyle(AppTheme.Text.secondaryColor).font(.system(size: AppTheme.FontSize.sm))
            } else if model.films.isEmpty {
                Text(L10n.string("No films yet — generate one and it shows up here"))
                    .foregroundStyle(AppTheme.Text.secondaryColor).font(.system(size: AppTheme.FontSize.sm))
            } else {
                if let e = model.error {
                    Text(e)
                        .foregroundStyle(AppTheme.Status.warningColor)
                        .font(.system(size: AppTheme.FontSize.sm))
                }
                // **一面墙，不是一份日志。**
                //
                // 这一屏列的是片子，而它原来长得像日志：一行提示词、
                // 一行「几镜 · 多少 credits · 多久以前」、右边一个状态词。
                // 而每一条成片都带 `shot_0.mp4` —— 我们手里有画面，他看不到。
                //
                // 卡片自适应铺开；鼠标停上去那一张自己动起来（静音播第一镜）。
                LazyVGrid(
                    columns: [GridItem(
                        .adaptive(minimum: AppTheme.FilmWall.cardMinWidth),
                        spacing: AppTheme.Spacing.md, alignment: .top
                    )],
                    alignment: .leading,
                    spacing: AppTheme.Spacing.md
                ) {
                    ForEach(model.films) { f in
                        MetagFilmCard(
                            film: f,
                            poster: posters.poster(for: f.job_id),
                            onOpen: { onOpen(f) },
                            onShare: { Task { await model.share(f.job_id) } },
                            onDelete: { Task { await model.remove(f.job_id) } },
                            busy: model.busy != nil
                        )
                        .task(id: f.job_id) {
                            guard let name = f.poster else { return }
                            posters.load(jobId: f.job_id, name: name)
                        }
                    }
                }
            }
        }
        .task { await model.load() }
    }

    /// **跟界面语言走，而且每行不新建一个 formatter。**
    ///
    /// 原来写死 `"M/d HH:mm"` —— `9/1 04:55` 对欧洲用户是"1 月 9 日"，
    /// 这和第一天修掉的「英文界面里写着"1个月前"」是同一个毛病：
    /// 日期没跟着用户走。而 `DateFormatter()` 建在函数里，
    /// 一屏十行就建十次。
    ///
    /// 用 `AppLocalization.relativeString` —— 首页项目卡用的就是它
    /// （"7小时前"），同一个产品里同一种时间不该有两种写法。
    @MainActor
    static func when(_ epoch: Double) -> String {
        AppLocalization.shared.relativeString(
            for: Date(timeIntervalSince1970: epoch), style: .short
        )
    }
}
