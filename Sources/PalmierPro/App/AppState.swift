import SwiftUI
import UniformTypeIdentifiers

struct ProjectOpenOptions {
    var startTutorial = false
}

enum ProjectError: LocalizedError {
    case nameTaken(URL)
    case invalidName(String)
    case openProjects([String])
    case projectsOpening([String])
    case deletionInProgress(URL)

    var errorDescription: String? {
        switch self {
        case .nameTaken(let url):
            "A project named “\(url.deletingPathExtension().lastPathComponent)” already exists in that folder. Pick another name."
        case .invalidName(let name):
            "“\(name)” isn't a valid project name. Use a plain name without slashes or path components."
        case .openProjects(let names):
            "Close \(names.formatted()) before deleting."
        case .projectsOpening(let names):
            "Wait for \(names.formatted()) to finish opening before deleting."
        case .deletionInProgress(let url):
            "“\(url.deletingPathExtension().lastPathComponent)” is being moved to the Trash."
        }
    }
}

@Observable
@MainActor
final class AppState {
    static let shared = AppState()

    private(set) var activeProject: VideoProject?

    /// 他打完那一句、按下去之后，还没送到面板手上的那一份。
    ///
    /// ## 为什么不能只靠一条通知
    ///
    /// `startFilm` 建完工程就 `showWindows()`，紧接着发 `.metagStartDraft`。
    /// 而听它的是编辑器里的 `MediaTab` —— 一个 SwiftUI 视图，
    /// **它的 `.onReceive` 要等第一次渲染才订阅上**。
    /// 窗口刚 `showWindows()` 返回那一刻，它订阅上了没有，取决于当时机器多忙。
    ///
    /// 赢了竞态就一切正常，输了的样子是：**他打了字、按了钮，
    /// 落进一个空编辑器，什么都没发生。** 而那正是我们最贵的那一次交互。
    ///
    /// 2026-09-04 刚在引导层上修过同一个形状（那条通知一个接收者都没有），
    /// 这一条是它的孪生兄弟 —— 有接收者，但可能还没醒。
    ///
    /// 所以改成**顺序无关**：先把它放在这儿，通知照发。
    /// 面板醒着就当场收到；醒得晚就在 `onAppear` 里自己来取。
    /// 取走即清 —— **一份草案只该开一次**。
    struct PendingDraft: Equatable {
        let prompt: String?
        let assets: [URL]
    }
    private(set) var pendingDraft: PendingDraft?

    func queueDraft(prompt: String?, assets: [URL]) {
        pendingDraft = PendingDraft(prompt: prompt, assets: assets)
    }

    /// 面板来取。**取走即清**，第二个面板不会再开一张。
    func takePendingDraft() -> PendingDraft? {
        defer { pendingDraft = nil }
        return pendingDraft
    }
    private var projectPathsBeingDeleted: Set<String> = []
    private var projectOpenCounts: [String: Int] = [:]

    var openProjects: [VideoProject] {
        NSDocumentController.shared.documents.compactMap { $0 as? VideoProject }
    }

    private(set) var mcpService: MCPService?

    func startMCPService() {
        guard mcpService == nil else { return }
        guard MCPService.isEnabledPreference else {
            Log.mcp.notice("mcp disabled in settings; not starting")
            return
        }
        let service = MCPService(projectProvider: { [weak self] in
            self?.activeProject
        })
        service.start()
        mcpService = service
    }

    func stopMCPService() {
        mcpService?.stop()
        mcpService = nil
    }

    /// Routed through the live service when there is one so rotation also revokes open sessions.
    func rotateMCPAccessToken() async throws -> String {
        if let mcpService { return try await mcpService.rotateAccessToken() }
        return try await MCPAccessTokenStore.shared.rotate()
    }

    func setMCPEnabled(_ enabled: Bool) {
        MCPService.isEnabledPreference = enabled
        if enabled {
            startMCPService()
        } else {
            stopMCPService()
        }
    }

    func showHome() {
        guard let project = activeProject else {
            HomeWindowController.shared.showWindow(nil)
            return
        }
        let presentHome = {
            if let url = project.fileURL {
                ProjectRegistry.shared.register(url)
            }
            project.windowControllers.forEach { $0.window?.orderOut(nil) }
            if self.activeProject === project {
                self.activeProject = nil
            }
            HomeWindowController.shared.showWindow(nil)
        }
        if project.isDocumentEdited {
            project.autosave(withImplicitCancellability: false) { _ in
                DispatchQueue.main.async {
                    presentHome()
                }
            }
        } else {
            presentHome()
        }
    }

    func showEditor(for project: VideoProject) {
        activateProject(project)
        project.showWindows()
        hideHomeIfEditorIsVisible(for: project)
    }

    func activateProject(_ project: VideoProject) {
        if activeProject !== project {
            activeProject = project
            project.editorViewModel.refreshProjectId()
            recordProjectActive(project)
        }
    }

    func projectWindowDidBecomeKey(_ project: VideoProject) {
        activateProject(project)
        hideHomeIfEditorIsVisible(for: project)
    }

    private func hideHomeIfEditorIsVisible(for project: VideoProject) {
        guard project.windowControllers.contains(where: { $0.window?.isVisible == true }) else { return }
        HomeWindowController.shared.window?.orderOut(nil)
    }

    // Save and close project; switch to next open or show Home. Throws (without closing) if the save fails.
    func closeProject(_ project: VideoProject) async throws {
        if let url = project.fileURL { ProjectRegistry.shared.register(url) }
        try await project.saveBeforeClosing()
        let wasActive = activeProject === project
        project.close()
        if wasActive {
            activeProject = nil
            if let next = openProjects.first {
                showEditor(for: next)
            } else {
                HomeWindowController.shared.showWindow(nil)
            }
        }
    }

    func revealGeneratedAssetFromNotification(assetId: String?, projectURL: URL?) {
        NSApp.activate(ignoringOtherApps: true)
        guard let project = notificationTargetProject(assetId: assetId, projectURL: projectURL) else {
            if activeProject == nil {
                HomeWindowController.shared.showWindow(nil)
            }
            return
        }

        showEditor(for: project)
        project.windowControllers.first?.window?.makeKeyAndOrderFront(nil)

        guard let assetId,
              let asset = project.editorViewModel.mediaAssets.first(where: { $0.id == assetId }) else {
            return
        }

        let editor = project.editorViewModel
        editor.mediaPanelVisible = true
        editor.maximizedPanel = nil
        editor.focusedPanel = .media
        editor.selectMediaAsset(asset)
        editor.mediaPanelRevealAssetId = assetId
    }

    private func notificationTargetProject(assetId: String?, projectURL: URL?) -> VideoProject? {
        if let projectURL {
            return openProjects.first { Self.sameFile($0.fileURL, projectURL) }
        }
        if let assetId {
            return openProjects.first { project in
                project.editorViewModel.mediaAssets.contains { $0.id == assetId }
            }
        }
        return activeProject
    }

    private static func sameFile(_ lhs: URL?, _ rhs: URL) -> Bool {
        guard let lhs else { return false }
        return lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    // MARK: - Project lifecycle

    // Creates and displays a project at `url`; doesn't save or register.
    private func instantiateProject(at url: URL) -> VideoProject {
        let doc = VideoProject()
        doc.fileURL = url
        doc.fileType = VideoProject.typeIdentifier
        doc.makeWindowControllers()
        NSDocumentController.shared.addDocument(doc)
        showEditor(for: doc)
        return doc
    }

    /// Creates a new project in the storage folder; errors if the name is invalid or already taken.
    @discardableResult
    func createProject(named name: String) async throws -> VideoProject {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? Project.defaultProjectName : trimmed
        guard !base.contains("/"), !base.contains("\\"), base != ".", base != ".." else {
            throw ProjectError.invalidName(base)
        }
        let directory = Project.storageDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(base).appendingPathExtension(Project.fileExtension)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw ProjectError.nameTaken(url)
        }
        let previous = activeProject
        let doc = instantiateProject(at: url)
        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                doc.save(to: url, ofType: VideoProject.typeIdentifier, for: .saveOperation) { error in
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                }
            }
        } catch {
            doc.close()
            try? FileManager.default.removeItem(at: url)
            if let previous { showEditor(for: previous) }
            throw error
        }
        ProjectRegistry.shared.register(url)
        doc.editorViewModel.refreshProjectId()
        recordProjectCreated(doc)
        recordProjectOpened(doc)
        return doc
    }

    /// 从他写的那一句开始一部片子。**不弹存储面板。**
    ///
    /// 他要的是片子，不是先给文件起个名 —— 所以项目名就用那句话
    /// （顺带治掉列表里那些 `tl-074321` 的机器名）。名字撞了就往后加序号，
    /// 而不是弹一个错误让他重来。
    @MainActor
    func startFilm(from line: String, assets: [URL] = []) async {
        let name = Self.projectName(from: line)
        do {
            var attempt = name
            var n = 2
            while true {
                do {
                    let project = try await createProject(named: attempt)
                    showEditor(for: project)
                    break
                } catch ProjectError.nameTaken {
                    attempt = "\(name) \(n)"
                    n += 1
                    if n > 50 { throw ProjectError.nameTaken(Project.storageDirectory) }
                }
            }
        } catch {
            Log.project.error("start film from line failed: \(error.localizedDescription)")
            return
        }
        // 项目开好了再把草案面板端上来：面板活在编辑器的媒体面板里，
        // 而首页那一刻还没有项目。
        handOffDraft(prompt: line, assets: assets)
    }

    /// 把那一句交给面板。**两条路都留着** —— 面板醒着走通知，醒得晚走排队那一份。
    ///
    /// 抽出来是因为判据够不着 `startFilm`（它要真的建一个工程、开一扇窗）。
    /// 而"到底排没排队"正是这件事的全部：第一版我只测了 `queueDraft` 本身，
    /// **把 `startFilm` 里那一行删掉，判据照样全绿。**
    func handOffDraft(prompt: String?, assets: [URL]) {
        queueDraft(prompt: prompt, assets: assets)
        var info: [String: Any] = ["assets": assets]
        if let prompt { info["prompt"] = prompt }
        NotificationCenter.default.post(name: .metagStartDraft, object: nil, userInfo: info)
    }

    /// 打开他上一条片子 —— 从首页那一格进来。
    ///
    /// 和 `startFilm` 同一个形状（建工程 → 开编辑器 → 交给面板），
    /// **不是另起一条路**：铺时间线那一段只有 `MetagJobOpener` 知道怎么做，
    /// 而它要一个 editor，首页这一刻还没有。
    func openFilm(jobId: String, named line: String) async {
        let name = Self.projectName(from: line)
        do {
            var attempt = name
            var n = 2
            while true {
                do {
                    let project = try await createProject(named: attempt)
                    showEditor(for: project)
                    break
                } catch ProjectError.nameTaken {
                    attempt = "\(name) \(n)"
                    n += 1
                    if n > 50 { throw ProjectError.nameTaken(Project.storageDirectory) }
                }
            }
        } catch {
            Log.project.error("open film from home failed: \(error.localizedDescription)")
            return
        }
        NotificationCenter.default.post(
            name: .metagOpenFilm, object: nil, userInfo: ["jobId": jobId]
        )
    }

    /// 把一句话变成一个能当文件名的项目名。
    ///
    /// 只做三件事：去掉路径分隔符和首尾点、压掉连续空白、按**字符**截断。
    /// 按字符不按字节 —— 中文一句话很短，按字节截会砍在半个字上。
    nonisolated static func projectName(from line: String) -> String {
        let cleaned = line
            .components(separatedBy: CharacterSet(charactersIn: "/\\:"))
            .joined(separator: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let capped = String(cleaned.prefix(48)).trimmingCharacters(in: .whitespaces)
        return capped.isEmpty ? Project.defaultProjectName : capped
    }

    func createProjectInteractively() {
        Telemetry.beginOperation("save_panel", data: ["flow": "project_create"])
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.projectContentType]
        panel.nameFieldStringValue = Project.defaultProjectName
        panel.directoryURL = Project.storageDirectory
        panel.title = L10n.string("New Project")
        panel.begin { [self] response in
            Telemetry.endOperation("save_panel")
            guard response == .OK, let url = panel.url else { return }
            let doc = instantiateProject(at: url)
            doc.save(to: url, ofType: VideoProject.typeIdentifier, for: .saveOperation) { error in
                guard error == nil else { return }
                ProjectRegistry.shared.register(url)
                doc.editorViewModel.refreshProjectId()
                self.recordProjectCreated(doc)
                self.recordProjectOpened(doc)
            }
        }
    }

    func openProject(at url: URL, register: Bool = true, options: ProjectOpenOptions = .init()) {
        Task {
            do {
                try await openProjectAsync(at: url, register: register, options: options)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    @discardableResult
    func openProjectAsync(at url: URL, register: Bool = true, options: ProjectOpenOptions = .init()) async throws -> VideoProject {
        try Task.checkCancellation()
        let resolved = url.standardizedFileURL
        guard !projectPathsBeingDeleted.contains(resolved.path) else {
            throw ProjectError.deletionInProgress(resolved)
        }
        if let existing = showExistingProject(at: resolved, register: register, options: options) {
            return existing
        }
        projectOpenCounts[resolved.path, default: 0] += 1
        defer {
            if projectOpenCounts[resolved.path] == 1 {
                projectOpenCounts[resolved.path] = nil
            } else {
                projectOpenCounts[resolved.path, default: 1] -= 1
            }
        }
        let doc = try await VideoProject.load(from: resolved)
        try Task.checkCancellation()
        guard !projectPathsBeingDeleted.contains(resolved.path) else {
            throw ProjectError.deletionInProgress(resolved)
        }
        if let existing = showExistingProject(at: resolved, register: register, options: options) {
            return existing
        }

        doc.makeWindowControllers()
        NSDocumentController.shared.addDocument(doc)
        showEditor(for: doc)
        if register { ProjectRegistry.shared.register(resolved) }
        doc.editorViewModel.refreshProjectId()
        recordProjectOpened(doc)
        apply(options, to: doc.editorViewModel)
        return doc
    }

    func deleteProjects(withIDs ids: Set<UUID>) async throws -> ProjectDeletionResult {
        let entries = ProjectRegistry.shared.entries.filter { ids.contains($0.id) }
        let openPaths = Set(openProjects.compactMap { $0.fileURL?.standardizedFileURL.path })
        let openEntries = entries.filter { openPaths.contains($0.url.standardizedFileURL.path) }
        guard openEntries.isEmpty else {
            throw ProjectError.openProjects(openEntries.map(\.name))
        }
        let openingEntries = entries.filter { projectOpenCounts[$0.url.standardizedFileURL.path] != nil }
        guard openingEntries.isEmpty else {
            throw ProjectError.projectsOpening(openingEntries.map(\.name))
        }

        let paths = Set(entries.map { $0.url.standardizedFileURL.path })
        if let path = paths.first(where: { projectPathsBeingDeleted.contains($0) }) {
            throw ProjectError.deletionInProgress(URL(fileURLWithPath: path))
        }
        projectPathsBeingDeleted.formUnion(paths)
        defer { projectPathsBeingDeleted.subtract(paths) }
        return await ProjectRegistry.shared.delete(entries)
    }

    private func showExistingProject(at url: URL, register: Bool, options: ProjectOpenOptions) -> VideoProject? {
        if let existing = openProjects.first(where: { Self.sameFile($0.fileURL, url) }) {
            if register { ProjectRegistry.shared.register(url) }
            showEditor(for: existing)
            apply(options, to: existing.editorViewModel)
            return existing
        }
        return nil
    }

    private func recordProjectCreated(_ project: VideoProject) {
        Analytics.capture(.projectCreated, properties: project.editorViewModel.analyticsSnapshot())
    }

    private func recordProjectOpened(_ project: VideoProject) {
        let properties = project.editorViewModel.analyticsSnapshot()
        Analytics.capture(.projectOpened, properties: properties)
        if let projectId = project.editorViewModel.projectId {
            Analytics.captureProjectActive(projectId: projectId, properties: properties)
        }
    }

    private func recordProjectActive(_ project: VideoProject) {
        guard let projectId = project.editorViewModel.projectId else { return }
        let properties = project.editorViewModel.analyticsSnapshot()
        Analytics.captureProjectActive(projectId: projectId, properties: properties)
    }

    private func apply(_ options: ProjectOpenOptions, to editor: EditorViewModel) {
        if options.startTutorial {
            DispatchQueue.main.async { editor.tour.start(in: editor) }
        }
    }

    func openSample(slug: String, startTutorial: Bool, onProgress: @escaping (Double) -> Void = { _ in }) async throws {
        let options = ProjectOpenOptions(startTutorial: startTutorial)
        if let cached = SampleProjectService.shared.cachedURL(slug: slug) {
            try await openProjectAsync(at: cached, register: false, options: options)
            return
        }
        let url = try await SampleProjectService.shared.materialize(slug: slug, onProgress: onProgress)
        try await openProjectAsync(at: url, register: false, options: options)
    }

    func openProjectFromPanel() {
        Telemetry.beginOperation("open_panel", data: ["flow": "project_open"])
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.projectContentType]
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = L10n.string("Open Project")
        panel.begin { response in
            Telemetry.endOperation("open_panel")
            guard response == .OK, let url = panel.url else { return }
            AppState.shared.openProject(at: url)
        }
    }

    private static let projectContentType: UTType = {
        UTType(Project.typeIdentifier)
            ?? UTType(filenameExtension: Project.fileExtension, conformingTo: .package)
            ?? .package
    }()

}
