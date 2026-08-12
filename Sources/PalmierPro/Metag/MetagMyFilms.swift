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

    var failedCount: Int { films.filter { $0.status == "failed" }.count }

    /// 删一条。**乐观移除**：服务端已经删掉了，再拉一次列表只是让用户多等一轮。
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
                Text(L("My films")).font(.headline)
                Spacer()
                if model.failedCount > 0 {
                    Button(model.busy == "__all__"
                           ? L("Clearing…")
                           : L("Clear %@ failed", model.failedCount.formatted())) {
                        Task { await model.clearFailed() }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .disabled(model.busy != nil)
                }
            }
            if model.loading && model.films.isEmpty {
                Text(L("Loading…")).foregroundStyle(.secondary).font(.caption)
            } else if let e = model.error {
                Text(e).foregroundStyle(.secondary).font(.caption)
            } else if model.films.isEmpty {
                Text(L("No films yet — generate one and it shows up here"))
                    .foregroundStyle(.secondary).font(.caption)
            } else {
                ForEach(model.films) { f in
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Button { onOpen(f) } label: { row(f) }
                            .buttonStyle(.plain)
                            .disabled(!f.retrievable || model.busy != nil)
                            .opacity(f.retrievable ? 1 : 0.55)
                        Button {
                            Task { await model.remove(f.job_id) }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: AppTheme.FontSize.xs))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(model.busy != nil)
                        .help(L("Delete"))
                    }
                }
            }
        }
        .task { await model.load() }
    }

    private func row(_ f: MetagGateway.FilmRow) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(f.prompt ?? L("Untitled")).lineLimit(1)
                Text(L("%@ shots · %@ credits", f.shots.formatted(), f.credits.formatted()) + " · " + Self.when(f.created_at))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            // 如实说：这一单的产物已经不在了。含糊其辞比说不出口更伤信任。
            Text(f.status == "failed" ? L("Failed")
                 : (f.retrievable ? L("Open") : L("Expired")))
                .font(.caption)
                .foregroundStyle(f.status == "failed" ? .orange
                                 : (f.retrievable ? Color.accentColor : .orange))
        }
        .contentShape(Rectangle())
    }

    private static func when(_ epoch: Double) -> String {
        let d = Date(timeIntervalSince1970: epoch)
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        return f.string(from: d)
    }
}
