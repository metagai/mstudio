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
            let wanted = MetagNarrationPlan.shotsToOpen(
                shots: job.shots.count, status: job.status, salvaged: job.salvaged
            )
            guard !wanted.isEmpty else {
                editor.mediaPanelToast = MediaPanelToast(
                    message: L10n.key("This film has no usable shots."))
                return
            }
            let native = MetagNarrationPlan.nativeAudioEngineIds(try? await MetagGateway.pricing())
            let needsNarration = Set(MetagNarrationPlan.shotsNeedingNarration(
                shots: job.shots.count, shotEngines: job.shot_engines, nativeAudioEngineIds: native
            ))

            var added = 0
            var narrations = 0
            for i in wanted {
                let shot = job.shots[i]
                if let url = try? await MetagGateway.download(
                    job: jobId, name: shot.video, to: FileManager.default.temporaryDirectory) {
                    // addMediaAsset 返回非可选，原来那句 `!= nil` 恒真、每次构建都报警告。
                    // 计数没错过（它本来就总会加），错的是那句判断在假装自己在判断。
                    editor.addMediaAsset(from: url, type: .video)
                    added += 1
                }
                // 原生出声的那几镜不取旁白 —— 取回来只会被用户铺到模型自己的声音上面。
                guard needsNarration.contains(i), !shot.audio.isEmpty else { continue }
                if let url = try? await MetagGateway.download(
                    job: jobId, name: shot.audio, to: FileManager.default.temporaryDirectory) {
                    editor.addMediaAsset(from: url, type: .audio)
                    narrations += 1
                }
            }
            editor.mediaPanelToast = MediaPanelToast(
                message: message(added: added, narrations: narrations, salvaged: job.status == "failed"),
                kind: added > 0 ? .success : .warning
            )
        } catch {
            editor.mediaPanelToast = MediaPanelToast(message: error.localizedDescription)
        }
    }

    @MainActor

    private static func message(added: Int, narrations: Int, salvaged: Bool) -> String {
        // 取不到就直说。含糊其辞比说不出口更伤信任。
        guard added > 0 else {
            return L10n.key("Those files have expired and cannot be opened.")
        }
        // 抢救回来的要说清楚它是残的，否则用户以为整单都在手上。
        if salvaged {
            return L10n.string("Kept the \(added.formatted()) shots that rendered before this one failed.")
        }
        // 旁白条数单独说：原生出声的档位一条都不会有，用户不该以为旁白丢了。
        return narrations > 0
            ? L10n.string("Loaded \(added.formatted()) shots and \(narrations.formatted()) narration tracks.")
            : L10n.string("Loaded \(added.formatted()) shots.")
    }
}
