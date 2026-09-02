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
                let kind = MetagFailureKind(job.error_kind)
                // **这一次尝试原来一个字都不记。** 分母缺了失败，
                // 成功率就不是成功率，是"成功的人里有多少成功了"。
                //
                // `why` 用网关白名单里的三种；**真实种类另记一格** ——
                // 那是网关分出来的，比我们在客户端猜准。
                MetagFunnel.track(.filmFailed, meta: [
                    "why": (job.status == "failed"
                            ? MetagFunnel.FailureReason.renderFailed
                            : .noShots).rawValue,
                    "kind": kind.rawValue,
                    "shots": job.shots.count,
                ])
                // **三种失败要说的话完全不一样，说错一种比不说更糟。**
                //
                // 2026-09-01 上午我把这里改成过「换个说法或者换一档再试」——
                // 那是给内容判回的话，却发给了所有人。对着一次上游 503 说这句，
                // 他会去改一句根本没问题的话、改完再失败一次，
                // **我们把自己的故障算在了他头上**。
                //
                // 而分类一直在响应里（`error_kind`），只是客户端从没解过它。
            editor.mediaPanelToast = MediaPanelToast(message: kind.message)
                return
            }
            let native = MetagNarrationPlan.nativeAudioEngineIds(try? await MetagGateway.pricing())
            let needsNarration = Set(MetagNarrationPlan.shotsNeedingNarration(
                shots: job.shots.count, shotEngines: job.shot_engines, nativeAudioEngineIds: native
            ))

            // 先把素材取全，**取完再一次铺上去** —— 边下边铺的话，
            // 撤销会变成 N 步，而他做的只是"打开一条片子"这一件事。
            var shotAssets: [(index: Int, asset: MediaAsset)] = []
            var narrationAssets: [(index: Int, asset: MediaAsset)] = []
            for i in wanted {
                let shot = job.shots[i]
                if let url = try? await MetagGateway.download(
                    job: jobId, name: shot.video, to: FileManager.default.temporaryDirectory) {
                    // addMediaAsset 返回非可选，原来那句 `!= nil` 恒真、每次构建都报警告。
                    // 计数没错过（它本来就总会加），错的是那句判断在假装自己在判断。
                    shotAssets.append((i, editor.addMediaAsset(from: url, type: .video)))
                }
                // 原生出声的那几镜不取旁白 —— 取回来只会被用户铺到模型自己的声音上面。
                guard needsNarration.contains(i), !shot.audio.isEmpty else { continue }
                if let url = try? await MetagGateway.download(
                    job: jobId, name: shot.audio, to: FileManager.default.temporaryDirectory) {
                    narrationAssets.append((i, editor.addMediaAsset(from: url, type: .audio)))
                }
            }
            let added = shotAssets.count
            let narrations = narrationAssets.count
            // 有镜可取、却一条都没取下来 —— 取件过期。他等完了，手上还是空的。
            if added == 0 {
                MetagFunnel.track(.filmFailed, meta: [
                    "why": MetagFunnel.FailureReason.expired.rawValue,
                    "shots": job.shots.count,
                ])
            }
            // **配乐。** 网关专门把它从混音里分出来，就是为了让编辑器铺在
            // 那几段下面 —— 而 Mac 一直没下过它：用户看的是一条有配乐的草案，
            // 批准之后拿到的时间线上只有画面和旁白。
            // **他看的那条片子，和他拿到的那条不是同一条。**
            //
            // 放在镜头之后取：先让画面到手。取不到不影响已经铺好的那几段，
            // 但**要说出来** —— 少了配乐他会以为是我们没做，而不是没取到。
            var scoreAsset: MediaAsset?
            if added > 0, let bed = job.music_bed, !bed.isEmpty,
               let url = try? await MetagGateway.download(
                job: jobId, name: bed, to: FileManager.default.temporaryDirectory) {
                scoreAsset = editor.addMediaAsset(from: url, type: .audio)
            }
            let score = scoreAsset != nil

            // **把片子铺到时间线上。**
            //
            // 在此之前 `addMediaAsset` 只把素材加进库 —— 用户写一句话、
            // 等九十秒、付了 credits，拿到的是素材库里 N 个散文件和一条空时间线。
            // 这个产品的承诺是"一句话变成一条片子"，交付的是一堆配料。
            //
            // 整件事一步撤销：他做的是"打开一条片子"这一个动作。
            if added > 0 {
                editor.undo.perform(L10n.string("Add Film")) {
                    // 画面一条轨、声音一条轨。**新建工程的时间线是空的**，
                    // 所以先把轨道立起来 —— `addClips` 只往已有的轨上放。
                    editor.timeline.tracks.insert(Track(type: .audio), at: 0)
                    editor.timeline.tracks.insert(Track(type: .video), at: 0)

                    editor.addClips(assets: shotAssets.map(\.asset), trackIndex: 0, startFrame: 0)

                    // 旁白对齐到各自那一镜的起点 —— 它比镜头短，
                    // 一段接一段挨着放会越走越偏，第四镜的话会压在第三镜上。
                    // **这里没有 fps 可传** —— 起点按秒算，换算由时间线自己做。
                    let starts = MetagFilmLayout.startSeconds(
                        shotCount: shotAssets.count,
                        clipSeconds: job.shot_clips?.map(\.seconds),
                        measured: { shotAssets[$0].asset.duration }
                    ).map(editor.frame(atSeconds:))
                    let placements = MetagFilmLayout.narrationFrames(
                        shots: shotAssets.map(\.index),
                        narrations: Set(narrationAssets.map(\.index)),
                        starts: starts
                    )
                    for (shot, frame) in placements {
                        guard let narration = narrationAssets.first(where: { $0.index == shot })
                        else { continue }
                        editor.addClips(assets: [narration.asset], trackIndex: 1, startFrame: frame)
                    }

                    if let bed = scoreAsset {
                        editor.timeline.tracks.append(Track(type: .audio))
                        editor.addClips(assets: [bed], trackIndex: editor.timeline.tracks.count - 1,
                                        startFrame: 0)
                    }
                }
            }

            // **字幕。** 片子自带词级字幕（网关逐句合成时就对齐好了），
            // 而这个面板此前拿字幕的唯一办法是转写这条片子自己的旁白 ——
            // 慢、要联网、要额度，**而且不可能比原文更准：那段话本来就是我们写的**。
            //
            // 单独一步撤销（"Add Captions"）：它改了他的时间线，
            // 而他要的是片子 —— 一次 ⌘Z 就能拿掉。
            var captioned = false
            if added > 0, let subs = job.subtitles {
                let cues = MetagSubtitles.cues(from: subs)
                if !cues.isEmpty,
                   let specs = try? await CaptionSpecBuilder.build(
                    cues: cues, fps: editor.timeline.fps,
                    canvasWidth: editor.timeline.width, canvasHeight: editor.timeline.height,
                    style: .caption, center: AppTheme.Caption.defaultCenter),
                   !specs.isEmpty {
                    captioned = !editor.placeCaptionTrack(specs, actionName: "Add Captions").isEmpty
                }
            }

            editor.mediaPanelToast = MediaPanelToast(
                message: message(added: added, narrations: narrations, captioned: captioned,
                                 score: score, salvaged: job.status == "failed"),
                kind: added > 0 ? .success : .warning,
                // **他刚拿到片子，这一刻请他留住它。**
                // 「愿不愿意导出」就是我们量的那个内容质量指标，而在此之前
                // 那件事只存在于菜单栏第二层 —— 我们从没在他最想留住它的时候
                // 开过口。取不到片子时不挂：没有东西可导。
                action: added > 0 ? .export : nil
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

    private static func message(added: Int, narrations: Int, captioned: Bool,
                                score: Bool, salvaged: Bool) -> String {
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
        // 配乐单独说一句。**少了它他会以为是我们没做**，而不是没取到。
        if !score {
            return narrations > 0
                ? L10n.string("Loaded \(added.formatted()) shots and \(narrations.formatted()) narration tracks — no score.")
                : L10n.string("Loaded \(added.formatted()) shots — no score.")
        }
        // 字幕铺上了就说一句 —— 他没要过它，得知道它在那儿、也知道能撤掉。
        if captioned {
            return L10n.string("Loaded \(added.formatted()) shots, with score and captions.")
        }
        return narrations > 0
            ? L10n.string("Loaded \(added.formatted()) shots and \(narrations.formatted()) narration tracks.")
            : L10n.string("Loaded \(added.formatted()) shots.")
    }
}
