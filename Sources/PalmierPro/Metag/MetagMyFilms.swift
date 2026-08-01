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
            Text("我的作品")
                .font(.headline)
            if model.loading && model.films.isEmpty {
                Text("加载中…").foregroundStyle(.secondary).font(.caption)
            } else if let e = model.error {
                Text(e).foregroundStyle(.secondary).font(.caption)
            } else if model.films.isEmpty {
                Text("还没有作品 —— 生成一条就会出现在这里")
                    .foregroundStyle(.secondary).font(.caption)
            } else {
                ForEach(model.films) { f in
                    Button { onOpen(f) } label: { row(f) }
                        .buttonStyle(.plain)
                        .disabled(!f.retrievable)
                        .opacity(f.retrievable ? 1 : 0.55)
                }
            }
        }
        .task { await model.load() }
    }

    private func row(_ f: MetagGateway.FilmRow) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(f.prompt ?? "未命名").lineLimit(1)
                Text("\(f.shots) 镜 · \(f.credits) credits · \(Self.when(f.created_at))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            // 如实说：这一单的产物已经不在了。含糊其辞比说不出口更伤信任。
            Text(f.retrievable ? "打开" : "产物已过期")
                .font(.caption)
                .foregroundStyle(f.retrievable ? Color.accentColor : .orange)
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
