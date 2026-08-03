import AppKit

/// Builds the application main menu with keyboard shortcuts.
/// Called from AppDelegate to wire shortcuts into the responder chain.
@MainActor
enum MainMenuBuilder {

    static func buildMenu() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenu())
        mainMenu.addItem(fileMenu())
        mainMenu.addItem(editMenu())
        mainMenu.addItem(viewMenu())
        mainMenu.addItem(helpMenu())
        return mainMenu
    }

    // MARK: - App menu

    private static func appMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "METAG")
        menu.addItem(withTitle: L("About METAG"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        let updatesItem = NSMenuItem(title: L("Check for Updates…"), action: #selector(Updater.checkForUpdates(_:)), keyEquivalent: "")
        updatesItem.target = Updater.shared
        menu.addItem(updatesItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Settings…"), action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Quit METAG"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = menu
        return item
    }

    // MARK: - File menu

    private static func fileMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: L("File"))
        let newItem = menu.addItem(withTitle: L("New"), action: #selector(AppDelegate.newProject(_:)), keyEquivalent: "n")
        newItem.target = NSApp.delegate
        let newFolderItem = NSMenuItem(title: L("New Folder"), action: #selector(EditorActions.newMediaFolder(_:)), keyEquivalent: "n")
        newFolderItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(newFolderItem)
        let openItem = menu.addItem(withTitle: L("Open…"), action: #selector(AppDelegate.openProject(_:)), keyEquivalent: "o")
        openItem.target = NSApp.delegate
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Save"), action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        menu.addItem(withTitle: L("Save As…"), action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "S")
        menu.addItem(.separator())

        let importItem = NSMenuItem(title: L("Import Media…"), action: #selector(EditorActions.importMedia(_:)), keyEquivalent: "i")
        importItem.keyEquivalentModifierMask = [.command]
        menu.addItem(importItem)

        menu.addItem(.separator())

        let exportItem = NSMenuItem(title: L("Export…"), action: #selector(EditorActions.showExport(_:)), keyEquivalent: "e")
        exportItem.keyEquivalentModifierMask = [.command]
        menu.addItem(exportItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Export Recipe…"), action: #selector(EditorActions.exportRecipe(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L("Import Recipe…"), action: #selector(EditorActions.importRecipe(_:)), keyEquivalent: ""))

        item.submenu = menu
        return item
    }

    // MARK: - Edit menu

    private static func editMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: L("Edit"))
        menu.addItem(withTitle: L("Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        menu.addItem(withTitle: L("Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: L("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: L("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: L("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())

        let selectForwardTrackItem = NSMenuItem(title: L("Select Forward on Track"), action: #selector(EditorActions.selectForwardOnTrack(_:)), keyEquivalent: "a")
        selectForwardTrackItem.keyEquivalentModifierMask = []
        menu.addItem(selectForwardTrackItem)

        let selectForwardAllItem = NSMenuItem(title: L("Select Forward on All Tracks"), action: #selector(EditorActions.selectForwardOnAllTracks(_:)), keyEquivalent: "a")
        selectForwardAllItem.keyEquivalentModifierMask = [.shift]
        menu.addItem(selectForwardAllItem)

        menu.addItem(.separator())

        let splitItem = NSMenuItem(title: L("Split at Playhead"), action: #selector(EditorActions.splitAtPlayhead(_:)), keyEquivalent: "k")
        splitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(splitItem)

        let trimStartItem = NSMenuItem(title: L("Trim Start to Playhead"), action: #selector(EditorActions.trimStartToPlayhead(_:)), keyEquivalent: "q")
        trimStartItem.keyEquivalentModifierMask = []
        menu.addItem(trimStartItem)

        let trimEndItem = NSMenuItem(title: L("Trim End to Playhead"), action: #selector(EditorActions.trimEndToPlayhead(_:)), keyEquivalent: "w")
        trimEndItem.keyEquivalentModifierMask = []
        menu.addItem(trimEndItem)

        menu.addItem(.separator())

        let deleteItem = NSMenuItem(title: L("Delete"), action: #selector(EditorActions.deleteSelectedClips(_:)), keyEquivalent: "\u{8}") // backspace
        deleteItem.keyEquivalentModifierMask = []
        menu.addItem(deleteItem)

        let rippleDeleteItem = NSMenuItem(title: L("Ripple Delete"), action: #selector(EditorActions.rippleDeleteSelected(_:)), keyEquivalent: "\u{8}") // backspace
        rippleDeleteItem.keyEquivalentModifierMask = [.shift]
        menu.addItem(rippleDeleteItem)

        item.submenu = menu
        return item
    }

    // MARK: - View menu

    private static func viewMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: L("View"))

        let mediaItem = NSMenuItem(title: L("Media Panel"), action: #selector(EditorActions.toggleMediaPanel(_:)), keyEquivalent: "0")
        mediaItem.keyEquivalentModifierMask = [.command]
        menu.addItem(mediaItem)

        let inspectorItem = NSMenuItem(title: L("Inspector Panel"), action: #selector(EditorActions.toggleInspectorPanel(_:)), keyEquivalent: "0")
        inspectorItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(inspectorItem)

        let agentItem = NSMenuItem(title: L("Agent Panel"), action: #selector(EditorActions.toggleAgentPanel(_:)), keyEquivalent: "a")
        agentItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(agentItem)

        menu.addItem(.separator())

        let maximizeItem = NSMenuItem(title: L("Maximize Focused Panel"), action: #selector(EditorActions.toggleMaximizePanel(_:)), keyEquivalent: "`")
        maximizeItem.keyEquivalentModifierMask = []
        menu.addItem(maximizeItem)

        menu.addItem(.separator())
        menu.addItem(layoutSubmenuItem())
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Enter Full Screen"), action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        item.submenu = menu
        return item
    }

    private static func layoutSubmenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: L("Layout"), action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: L("Layout"))

        let defaultItem = NSMenuItem(title: LayoutPreset.default.label, action: #selector(EditorActions.setLayoutDefault(_:)), keyEquivalent: "1")
        defaultItem.keyEquivalentModifierMask = [.command]
        submenu.addItem(defaultItem)

        let mediaItem = NSMenuItem(title: LayoutPreset.media.label, action: #selector(EditorActions.setLayoutMedia(_:)), keyEquivalent: "2")
        mediaItem.keyEquivalentModifierMask = [.command]
        submenu.addItem(mediaItem)

        let verticalItem = NSMenuItem(title: LayoutPreset.vertical.label, action: #selector(EditorActions.setLayoutVertical(_:)), keyEquivalent: "3")
        verticalItem.keyEquivalentModifierMask = [.command]
        submenu.addItem(verticalItem)

        item.submenu = submenu
        return item
    }

    // MARK: - Help menu

    private static func helpMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: L("Help"))
        menu.addItem(withTitle: L("Tutorial"), action: #selector(AppDelegate.showTutorial(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Keyboard Shortcuts"), action: #selector(AppDelegate.showKeyboardShortcuts(_:)), keyEquivalent: "?")
        menu.addItem(withTitle: L("MCP Instructions"), action: #selector(AppDelegate.showMCPInstructions(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Send Feedback…"), action: #selector(AppDelegate.showFeedback(_:)), keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

/// Actions dispatched through the responder chain to reach the active EditorViewModel.
@MainActor @objc protocol EditorActions {
    func splitAtPlayhead(_ sender: Any?)
    func trimStartToPlayhead(_ sender: Any?)
    func trimEndToPlayhead(_ sender: Any?)
    func selectForwardOnTrack(_ sender: Any?)
    func selectForwardOnAllTracks(_ sender: Any?)
    func deleteSelectedClips(_ sender: Any?)
    func rippleDeleteSelected(_ sender: Any?)
    func importMedia(_ sender: Any?)
    func newMediaFolder(_ sender: Any?)
    func showExport(_ sender: Any?)
    func exportRecipe(_ sender: Any?)
    func importRecipe(_ sender: Any?)
    func toggleMediaPanel(_ sender: Any?)
    func toggleInspectorPanel(_ sender: Any?)
    func toggleAgentPanel(_ sender: Any?)
    func toggleMaximizePanel(_ sender: Any?)
    func setLayoutDefault(_ sender: Any?)
    func setLayoutMedia(_ sender: Any?)
    func setLayoutVertical(_ sender: Any?)
}
