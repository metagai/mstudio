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
        let previousURL = asset.url
        do {
            try await MetagGateway.reshoot(job: job, shot: index, reroll: reroll, candidates: candidates)
        } catch {
            editor.mediaPanelToast = MediaPanelToast(message: message(for: error), kind: .warning)
            return
        }
        editor.mediaPanelToast = MediaPanelToast(message: L10n.key("Re-shooting — the new take replaces this shot when it lands."), kind: .progress)

        guard let take = await waitForTake(job: job, shot: index) else {
            editor.mediaPanelToast = MediaPanelToast(message: L10n.key("The re-shoot did not finish. Nothing was charged."), kind: .warning)
            return
        }
        do {
            let remote = try await MetagGateway.download(job: job, name: take, to: FileManager.default.temporaryDirectory)
            let installed = try await editor.commitStagedProjectMedia(remote, filename: remote.lastPathComponent)
            editor.undo.perform(L10n.key("Re-shoot")) {
                editor.registerTimelineUndo(L10n.key("Re-shoot")) { vm in
                    vm.relinkAsset(id: asset.id, to: previousURL)
                }
                editor.relinkAsset(id: asset.id, to: installed)
            }
            editor.mediaPanelToast = MediaPanelToast(message: L10n.key("New take is in the timeline."), kind: .success)
        } catch {
            editor.mediaPanelToast = MediaPanelToast(message: message(for: error), kind: .warning)
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
