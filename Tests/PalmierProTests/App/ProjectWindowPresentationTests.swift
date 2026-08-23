import AppKit
import Testing
@testable import PalmierPro

@Suite("Project window presentation", .serialized)
@MainActor
struct ProjectWindowPresentationTests {
    @Test func makingWindowControllersDoesNotPresentProject() {
        _ = NSApplication.shared
        let project = VideoProject()
        HomeWindowController.shared.showWindow(nil)
        defer { cleanUp(project) }

        project.makeWindowControllers()

        #expect(!project.windowControllers.isEmpty)
        #expect(project.windowControllers.allSatisfy { $0.window?.isVisible == false })
        #expect(AppState.shared.activeProject !== project)
        #expect(HomeWindowController.shared.window?.isVisible == true)
    }

    @Test func activationKeepsHomeVisibleUntilEditorIsPresented() {
        _ = NSApplication.shared
        let (project, editorWindow) = makeProjectWindow()
        HomeWindowController.shared.showWindow(nil)
        defer { cleanUp(project) }

        AppState.shared.activateProject(project)

        #expect(HomeWindowController.shared.window?.isVisible == true)
        #expect(!editorWindow.isVisible)

        AppState.shared.showEditor(for: project)

        #expect(editorWindow.isVisible)
        #expect(HomeWindowController.shared.window?.isVisible == false)
    }

    @Test func keyProjectWindowHidesHomeForDocumentControllerPresentation() {
        _ = NSApplication.shared
        let (project, editorWindow) = makeProjectWindow()
        HomeWindowController.shared.showWindow(nil)
        editorWindow.orderFront(nil)
        defer { cleanUp(project) }

        AppState.shared.projectWindowDidBecomeKey(project)

        #expect(AppState.shared.activeProject === project)
        #expect(editorWindow.isVisible)
        #expect(HomeWindowController.shared.window?.isVisible == false)
    }

    /// **走真接线，不直接调那个函数。**
    ///
    /// 上游自带的 `keyProjectWindowHidesHomeForDocumentControllerPresentation`
    /// 直接调 `AppState.shared.projectWindowDidBecomeKey(project)` —— 它测的是那个函数，
    /// 不是那条路。把 `VideoProject` 里装的回调改回 `activateProject`（也就是 #538 之前
    /// 的写法），它照样是绿的；而从 Finder 双击打开的项目正是靠这条回调让首页让开的，
    /// 改坏了就是"编辑器开在首页后面"。
    ///
    /// 这一条从 `makeWindowControllers()` 装好的那个 controller 出发，触发真正的
    /// `windowDidBecomeKey`，再看首页在不在。
    @Test func windowBecomingKeyThroughItsOwnDelegateHidesHome() {
        _ = NSApplication.shared
        let project = VideoProject()
        HomeWindowController.shared.showWindow(nil)
        defer { cleanUp(project) }

        project.makeWindowControllers()
        guard let controller = project.windowControllers.first as? EditorWindowController,
              let window = controller.window else {
            Issue.record("makeWindowControllers 没有装出 EditorWindowController")
            return
        }
        window.orderFront(nil)
        #expect(HomeWindowController.shared.window?.isVisible == true)

        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: window))

        #expect(AppState.shared.activeProject === project)
        #expect(HomeWindowController.shared.window?.isVisible == false)
    }

    private func makeProjectWindow() -> (VideoProject, NSWindow) {
        let project = VideoProject()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        project.addWindowController(NSWindowController(window: window))
        return (project, window)
    }

    private func cleanUp(_ project: VideoProject) {
        if AppState.shared.activeProject === project {
            AppState.shared.showHome()
        }
        for controller in project.windowControllers {
            controller.window?.orderOut(nil)
            project.removeWindowController(controller)
        }
        HomeWindowController.shared.window?.orderOut(nil)
    }
}
