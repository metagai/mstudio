import AppKit
import Foundation

/// Re-shoot one shot of a finished film from the timeline.
///
/// "This shot is wrong" is something you notice while cutting, not before. Without this the
/// only way out is regenerating the whole film, which throws away everything already edited.
@MainActor
enum MetagReshoot {

    /// A clip can be re-shot when we generated it and know how.
    static func eligibleShot(for asset: MediaAsset) -> (job: String, index: Int)? {
        guard let input = asset.generationInput,
              let job = input.backendJobId, !job.isEmpty,
              let index = input.outputIndex,
              input.model == "local"
        else { return nil }
        return (job, index)
    }

    /// Re-shoot, wait, then swap the clip's media to the new take.
    ///
    /// The previous take stays on the server and the previous file stays in the package, so
    /// undo is a repoint rather than a re-download.
    static func run(
        asset: MediaAsset,
        reroll: Bool,
        candidates: Int,
        editor: EditorViewModel
    ) async {
        guard let (job, index) = eligibleShot(for: asset) else { return }
        do {
            try await MetagGateway.reshoot(job: job, shot: index, reroll: reroll, candidates: candidates)
        } catch {
            editor.mediaPanelToast = MediaPanelToast(message: message(for: error), kind: .warning)
            return
        }
        editor.mediaPanelToast = MediaPanelToast(message: L10n.key("Re-shooting — the new take replaces this shot when it lands."), kind: .progress)

        guard await adoptNewTake(job: job, shot: index, asset: asset, editor: editor) else {
            // **上一版这里断言「没扣你钱」，而它有四条路走到这儿：**
            // 轮询十分钟超时（任务可能还在服务端跑、已经计费）、
            // 服务端真的失败、下载失败、以及**重拍其实成功了但他中途删了那个 clip**。
            // 后两种是钱已经花掉、货也做出来了 ——
            // 他随后在流水里看到一笔扣款，而我们刚刚当面对他说了一句假话。
            // **主动断言错的，比不说更糟。**
            editor.mediaPanelToast = MediaPanelToast(
                message: L10n.string("The re-shoot didn't finish. We're checking the credits — any refund shows up in credit activity."),
                kind: .warning)
            return
        }
        editor.mediaPanelToast = MediaPanelToast(message: L10n.key("New take is in the timeline."), kind: .success)
    }

    /// Re-run only the shots the quality gate flagged, then swap in whatever it improved.
    ///
    /// The gate only judges whether a shot is usable — frozen, flickering, solid colour.
    /// Whether a shot is *good* stays with the person, so nothing here picks on taste.
    static func fixFlagged(asset: MediaAsset, editor: EditorViewModel) async {
        guard let (job, _) = eligibleShot(for: asset) else { return }
        let result: MetagGateway.Converged
        do {
            result = try await MetagGateway.converge(job: job, rounds: 2, candidates: 2)
        } catch {
            editor.mediaPanelToast = MediaPanelToast(message: message(for: error))
            return
        }
        guard !result.queued.isEmpty else {
            // Say why. "Clicked and nothing happened" and "nothing needed fixing" look identical.
            let reason = result.skipped.first?.reason
            editor.mediaPanelToast = MediaPanelToast(
                message: reason.map { L10n.string("Nothing to fix — \($0)") }
                    ?? L10n.key("Nothing to fix."),
                kind: .success
            )
            return
        }
        editor.mediaPanelToast = MediaPanelToast(
            message: L10n.string("Fixing \(result.queued.count.formatted()) shots."),
            kind: .progress
        )
        // Download everything first, then swap in one transaction. One user intent has to
        // undo as one action, and `undo.perform` takes a synchronous closure — so the
        // awaits cannot live inside it. A shot that cannot be improved is skipped rather
        // than holding back the ones that were.
        var staged: [(asset: MediaAsset, from: URL, to: URL)] = []
        for shot in result.queued {
            guard let target = editor.asset(forJob: job, shotIndex: shot),
                  let take = await waitForTake(job: job, shot: shot)
            else { continue }
            do {
                let remote = try await MetagGateway.download(
                    job: job, name: take, to: FileManager.default.temporaryDirectory
                )
                let installed = try await editor.commitStagedProjectMedia(
                    remote, filename: remote.lastPathComponent
                )
                // The asset may have been deleted while we waited, so resolve it again.
                guard let current = editor.asset(forJob: job, shotIndex: shot) else { continue }
                staged.append((current, current.url, installed))
            } catch {
                editor.mediaPanelToast = MediaPanelToast(message: message(for: error))
            }
        }
        guard !staged.isEmpty else {
            editor.mediaPanelToast = MediaPanelToast(
                message: L10n.key("Nothing could be improved. Nothing was changed."),
                kind: .warning
            )
            return
        }
        editor.undo.perform(L10n.string("Fix Flagged Shots")) {
            editor.registerTimelineUndo(L10n.string("Fix Flagged Shots")) { vm in
                for item in staged { vm.relinkAsset(id: item.asset.id, to: item.from) }
            }
            for item in staged { editor.relinkAsset(id: item.asset.id, to: item.to) }
        }
        editor.mediaPanelToast = MediaPanelToast(
            message: L10n.string("Fixed \(staged.count.formatted()) shots."), kind: .success
        )
    }

    /// Wait for a shot's re-shoot and swap the clip's media to the result.
    @discardableResult
    private static func adoptNewTake(
        job: String,
        shot: Int,
        asset: MediaAsset,
        editor: EditorViewModel
    ) async -> Bool {
        guard let take = await waitForTake(job: job, shot: shot) else { return false }
        do {
            let remote = try await MetagGateway.download(job: job, name: take, to: FileManager.default.temporaryDirectory)
            let installed = try await editor.commitStagedProjectMedia(remote, filename: remote.lastPathComponent)
            // Waiting can take minutes; the clip may be gone by now. relinkAsset would
            // silently no-op and we would still report success, so check before claiming it.
            guard editor.mediaAssets.contains(where: { $0.id == asset.id }) else { return false }
            let previousURL = asset.url
            editor.undo.perform(L10n.string("Re-shoot")) {
                editor.registerTimelineUndo(L10n.string("Re-shoot")) { vm in
                    vm.relinkAsset(id: asset.id, to: previousURL)
                }
                editor.relinkAsset(id: asset.id, to: installed)
            }
            return true
        } catch {
            editor.mediaPanelToast = MediaPanelToast(message: message(for: error))
            return false
        }
    }

    /// Poll until this shot's re-shoot lands, then return the newest take's file name.
    private static func waitForTake(job: String, shot: Int) async -> String? {
        for _ in 0..<150 {
            try? await Task.sleep(for: .seconds(4))
            if Task.isCancelled { return nil }
            guard let detail = try? await MetagGateway.job(job) else { continue }
            let state = detail.reshoot?.indices.contains(shot) == true ? detail.reshoot?[shot] : nil
            guard let state else { continue }
            if state.hasPrefix("failed") { return nil }
            guard state == "done" else { continue }
            // Takes are ordered best first with the delivered one at index 0, so the newest
            // arrival is the last entry rather than the highest scoring one.
            return detail.alts?.indices.contains(shot) == true ? detail.alts?[shot].last?.file : nil
        }
        return nil
    }

    private static func message(for error: Error) -> String {
        if case MetagGateway.Failure.http(402) = error {
            return L10n.key("Re-shooting needs a subscription, and works only on shots made with our own engine.")
        }
        if case MetagGateway.Failure.http(429) = error {
            return L10n.key("Hourly limit reached. Try again later.")
        }
        return L10n.key("The re-shoot could not start.")
    }
}
