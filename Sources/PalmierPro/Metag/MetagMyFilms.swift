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
    @StateObject private var model = MetagMyFilmsModel()
    /// 点开一部作品要做什么，由调用方决定 —— 这个视图只负责"看得见、点得到"。
    var onOpen: (MetagGateway.FilmRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Text(L10n.key("My films")).font(.system(size: AppTheme.FontSize.mdLg, weight: AppTheme.FontWeight.semibold))
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
                Text(L10n.key("Link copied") + " · " + u)
                    .foregroundStyle(AppTheme.Text.secondaryColor).font(.system(size: AppTheme.FontSize.sm)).textSelection(.enabled)
            }
            if model.loading && model.films.isEmpty {
                Text(L10n.key("Loading…")).foregroundStyle(AppTheme.Text.secondaryColor).font(.system(size: AppTheme.FontSize.sm))
            } else if let e = model.error {
                Text(e).foregroundStyle(AppTheme.Text.secondaryColor).font(.system(size: AppTheme.FontSize.sm))
            } else if model.films.isEmpty {
                Text(L10n.key("No films yet — generate one and it shows up here"))
                    .foregroundStyle(AppTheme.Text.secondaryColor).font(.system(size: AppTheme.FontSize.sm))
            } else {
                ForEach(model.films) { f in
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Button { onOpen(f) } label: { row(f) }
                            .buttonStyle(.plain)
                            .disabled(!f.retrievable || model.busy != nil)
                            .opacity(f.retrievable ? AppTheme.Opacity.opaque : AppTheme.Opacity.medium)
                        // 他自己想炫耀是这门生意最便宜的一条获客路，而此前
                        // 一条做好的片子在全站没有任何办法递给第二个人。
                        Button {
                            Task { await model.share(f.job_id) }
                        } label: {
                            // **给它一个名字。** 这一屏存在的理由之一就是
                            // "他愿不愿意给别人看" —— 而那件事原来是一个
                            // 10 点的图标，要悬停才知道是什么。
                            HStack(spacing: AppTheme.Spacing.xxs) {
                                Image(systemName: "square.and.arrow.up")
                                Text(L10n.key("Share"))
                            }
                            .font(.system(size: AppTheme.FontSize.xs))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.Accent.brand)
                        .disabled(!f.retrievable || f.status != "done" || model.busy != nil)
                        .help(L10n.key("Send it to someone"))
                        Button {
                            Task { await model.remove(f.job_id) }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: AppTheme.FontSize.xs))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.Text.secondaryColor)
                        .disabled(model.busy != nil)
                        .help(L10n.key("Delete"))
                    }
                }
            }
        }
        .task { await model.load() }
    }

    private func row(_ f: MetagGateway.FilmRow) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(f.prompt ?? L10n.key("Untitled")).lineLimit(1)
                Text(L10n.string("\(f.shots.formatted()) shots · \(f.credits.formatted()) credits") + " · " + Self.when(f.created_at))
                    .font(.system(size: AppTheme.FontSize.sm)).foregroundStyle(AppTheme.Text.secondaryColor)
            }
            Spacer()
            // 如实说：这一单的产物已经不在了。含糊其辞比说不出口更伤信任。
            Text(f.status == "failed" ? L10n.key("Failed")
                 : (f.retrievable ? L10n.key("Open") : L10n.key("Expired")))
                .font(.system(size: AppTheme.FontSize.sm))
                // `systemOrange` 在纸底上 2.11:1，过不了 AA —— AppTheme 为此
                // 专门收敛过一版，而这里又把它写回来了（藏在三元里，
                // 判据的正则只认直写的那一种）。
                .foregroundStyle(f.status == "failed" || !f.retrievable
                                 ? AppTheme.Status.warningColor
                                 : AppTheme.Accent.brand)
        }
        .contentShape(Rectangle())
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
    private static func when(_ epoch: Double) -> String {
        AppLocalization.shared.relativeString(
            for: Date(timeIntervalSince1970: epoch), style: .short
        )
    }
}
