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
            // **片子到他手上了。** 记在"渲染完成"上是不对的：
            // 渲完但打不开、或者取件过期，用户手上什么都没有。
            // web 端就是靠这一格把「没到手」和「到了没看」切开的，
            // 那两半该改的东西完全相反。
            if !job.shots.isEmpty {
                MetagFunnel.track(.filmReady, meta: [
                    "shots": job.shots.count, "salvaged": job.salvaged,
                ])
            }
            guard !wanted.isEmpty else {
                // **这一次尝试原来一个字都不记。** 用户看到"没有可用镜头"，
                // 而漏斗里它根本不存在 —— 分母缺了失败，成功率就不是成功率，
                // 是"成功的人里有多少成功了"。
                MetagFunnel.track(.filmFailed, meta: [
                    "why": (job.status == "failed"
                            ? MetagFunnel.FailureReason.renderFailed
                            : .noShots).rawValue,
                    "shots": job.shots.count,
                ])
                editor.mediaPanelToast = MediaPanelToast(
                    // **他等完了，拿到一个句号。** 原来只说"没有可用镜头"——
                    // 不说为什么、不说下一步、也不说钱。钱这件事我不替网关承诺
                    // （退不退是它说了算），但**下一步必须给**。
                    message: L10n.key("None of the shots came back usable. Change a line or pick another tier, then try again."))
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
            // 有镜可取、却一条都没取下来 —— 取件过期。他等完了，手上还是空的。
            if added == 0 {
                MetagFunnel.track(.filmFailed, meta: [
                    "why": MetagFunnel.FailureReason.expired.rawValue,
                    "shots": job.shots.count,
                ])
            }
            editor.mediaPanelToast = MediaPanelToast(
                message: message(added: added, narrations: narrations, salvaged: job.status == "failed"),
                kind: added > 0 ? .success : .warning
            )
        } catch {
            // **这里我不记。**
            //
            // 连任务都问不到（网络断了？网关 5xx？任务被清了？）—— 我们不知道
            // 为什么，而 `why` 只有 `no_shots` / `render_failed` / `expired` 三种，
            // 硬塞一个进去就是给报表编一个原因。**宁可这一格少记，
            // 也不要记错。** 缺口已经报给网关那侧，等第四个取值。
            editor.mediaPanelToast = MediaPanelToast(message: error.localizedDescription)
        }
    }

    @MainActor

    private static func message(added: Int, narrations: Int, salvaged: Bool) -> String {
        // 取不到就直说。含糊其辞比说不出口更伤信任。
        guard added > 0 else {
            // 取件是内存盘，过期就真的没有了 —— 说清楚它要重做，
            // 而不是让他以为我们弄丢了。
            return L10n.key("These files have expired — this one needs generating again.")
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
