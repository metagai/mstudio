import Foundation

/// 把一部已完成的作品拉回时间轴。
///
/// 存在的理由：`myFilms` 列出了作品，但列表本身不解决"打开" ——
/// **一个点不开的列表，和没有列表没有区别。**
///
/// 下载走已有的那条路：本地内存盘上没有时，网关会 307 跳到对象存储，
/// 客户端察觉不到差别（见 gateway/src/delivery.rs）。
/// 这正是 2026-08-01 事故的修复：此前本地一清，任务仍"声称 done"而每一镜都 404。
enum MetagJobOpener {
    @MainActor
    static func open(jobId: String, into editor: EditorViewModel) async {
        do {
            let job = try await MetagGateway.job(jobId)
            guard !job.shots.isEmpty else {
                editor.mediaPanelToast = MediaPanelToast(
                    message: L10n.threadSafe("This film has no usable shots."))
                return
            }
            var added = 0
            for shot in job.shots {
                guard let url = try? await MetagGateway.download(
                    job: jobId, name: shot.video, to: FileManager.default.temporaryDirectory)
                else { continue }
                // addMediaAsset 返回非可选，原来那句 `!= nil` 恒真、每次构建都报警告。
                // 计数没错过（它本来就总会加），错的是那句判断在假装自己在判断。
                editor.addMediaAsset(from: url, type: .video)
                added += 1
            }
            editor.mediaPanelToast = MediaPanelToast(
                message: added > 0
                    // 取不到就直说。含糊其辞比说不出口更伤信任。
                    ? L10n.threadSafe("Loaded %@ shots.", [added.formatted()])
                    : L10n.threadSafe("Those files have expired and cannot be opened."),
                kind: added > 0 ? .success : .warning
            )
        } catch {
            editor.mediaPanelToast = MediaPanelToast(message: error.localizedDescription)
        }
    }
}
