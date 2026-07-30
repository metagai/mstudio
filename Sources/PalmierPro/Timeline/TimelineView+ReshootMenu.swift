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
        return menu
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
