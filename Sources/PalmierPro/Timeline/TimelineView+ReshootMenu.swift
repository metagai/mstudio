import AppKit

extension TimelineView {

    /// Re-shoot entries for a clip we generated. Absent for imported footage, which we
    /// cannot reproduce, and for paid engines, where re-running is not a menu-click decision.
    func reshootSubmenu(for clipId: String) -> NSMenu? {
        guard let asset = editor.generatedAsset(clipId: clipId),
              MetagReshoot.eligibleShot(for: asset) != nil
        else { return nil }

        let menu = NSMenu()
        menu.autoenablesItems = false
        let entries: [(String, Bool, Int)] = [
            (L10n.key("Re-shoot This Shot"), false, 1),
            (L10n.key("Another Composition"), true, 1),
            (L10n.key("Three More Takes"), true, 3),
        ]
        for (title, reroll, candidates) in entries {
            let item = NSMenuItem(title: title, action: #selector(performReshoot(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ["clipId": clipId, "reroll": reroll, "candidates": candidates]
            menu.addItem(item)
        }
        menu.addItem(.separator())
        // 挑一条：候选一直躺在 job.alts 里，而"Three More Takes"是自动采用最后一条。
        // 用户为几个候选付了钱，挑选权就该在他手里。
        let pick = NSMenuItem(title: L10n.key("Pick a Take…"), action: #selector(performPickTake(_:)), keyEquivalent: "")
        pick.target = self
        pick.representedObject = clipId
        pick.toolTip = L10n.key("Compare the takes this shot already has and choose one.")
        menu.addItem(pick)

        // Always offered rather than shown only when a shot is flagged: menu construction is
        // synchronous and the scores live on the server. Clicking says what it found, including
        // that nothing needed fixing.
        let fix = NSMenuItem(title: L10n.key("Fix Flagged Shots"), action: #selector(performFixFlagged(_:)), keyEquivalent: "")
        fix.target = self
        fix.representedObject = clipId
        fix.toolTip = L10n.key("Re-runs only shots the automatic check flagged. What you have is kept as a take.")
        menu.addItem(fix)
        return menu
    }

    @objc func performFixFlagged(_ sender: Any?) {
        guard let clipId = (sender as? NSMenuItem)?.representedObject as? String,
              let asset = editor.generatedAsset(clipId: clipId)
        else { return }
        let editor = self.editor
        Task { @MainActor in
            await MetagReshoot.fixFlagged(asset: asset, editor: editor)
        }
    }

    @objc func performPickTake(_ sender: Any?) {
        guard let clipId = (sender as? NSMenuItem)?.representedObject as? String,
              let asset = editor.generatedAsset(clipId: clipId),
              let (job, index) = MetagReshoot.eligibleShot(for: asset)
        else { return }
        editor.pendingTakePick = TakePick(job: job, shot: index, assetId: asset.id)
    }

    @objc func performReshoot(_ sender: Any?) {
        guard let info = (sender as? NSMenuItem)?.representedObject as? [String: Any],
              let clipId = info["clipId"] as? String,
              let asset = editor.generatedAsset(clipId: clipId)
        else { return }
        let reroll = info["reroll"] as? Bool ?? false
        let candidates = info["candidates"] as? Int ?? 1
        let editor = self.editor
        Task { @MainActor in
            await MetagReshoot.run(asset: asset, reroll: reroll, candidates: candidates, editor: editor)
        }
    }
}
