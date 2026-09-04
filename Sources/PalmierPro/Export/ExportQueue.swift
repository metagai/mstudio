import AppKit
import Foundation

enum ExportJobSource: String, Sendable {
    case manual
    case agent
    /// 首映条上那颗「留下它」—— 一次不问参数的保存。
    ///
    /// 单列一档不是为了改行为，是为了**在漏斗里认得出它**：
    /// `exported` 那一格记的就是 `source.rawValue`，
    /// 于是"他是自己配参数导的、还是按了留下它"能分开读。
    /// 2026-09-04 那一格是 0 —— 分不开也就无所谓，但它不该一直是 0。
    case keepIt
}

enum ExportJobStatus: String, Sendable {
    case waiting = "queued"
    case preparing
    case exporting = "rendering"
    case canceling
    case completed
    case failed
    case canceled

    var isRunning: Bool {
        switch self {
        case .preparing, .exporting, .canceling: true
        default: false
        }
    }

    var isFinished: Bool {
        switch self {
        case .completed, .failed, .canceled: true
        default: false
        }
    }

    var isPending: Bool { self == .waiting || isRunning }
}

/// 导出成功时要上报的时间线事实。**只有形状，没有内容** ——
/// 几个片段、多长、里面有没有 AI 生成的镜头。没有片名、没有提示词、没有画面。
struct FilmExportStats: Sendable {
    let shots: Int
    let seconds: Double
    let metag: Bool
}

struct ExportJob: Identifiable, Sendable {
    let id: UUID
    let projectID: String
    let filename: String
    let source: ExportJobSource
    let outputURL: URL
    let createdAt: Date
    var status: ExportJobStatus
    var progress: Double
    var error: String?
    var warnings: [String]
    var palmierReport: PalmierProjectExporter.Report?
    /// 导出成功后上报用。nil = 不上报（测试入队、工程文件导出等）。
    var stats: FilmExportStats?
}

struct ExportQueueSubmission: Sendable {
    let jobID: UUID
    let started: Bool
    let queuePosition: Int
}

enum ExportQueueError: LocalizedError {
    case destinationInUse(String)

    var errorDescription: String? {
        switch self {
        case .destinationInUse(let filename):
            "An export to \(filename) is already waiting or in progress."
        }
    }
}

@Observable
@MainActor
final class ExportQueue {
    static let shared = ExportQueue()

    typealias Operation = @MainActor (ExportService) async -> Void
    private(set) var jobs: [ExportJob] = []
    private var operations: [UUID: Operation] = [:]
    private var activeID: UUID?
    private var activeTask: Task<Void, Never>?
    private var activeService: ExportService?

    var hasActivity: Bool { jobs.contains { $0.status.isPending } }
    var isExportActive: Bool { activeID != nil }

    func waitWhileExportActive() async throws {
        while isExportActive {
            try await Task.sleep(for: .seconds(2))
        }
    }

    func jobs(for projectID: String) -> [ExportJob] {
        jobs.filter { $0.projectID == projectID }
    }

    func isDestinationReserved(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return jobs.contains { $0.status.isPending && $0.outputURL.standardizedFileURL.path == path }
    }

    @discardableResult
    func enqueueVideo(
        timeline: Timeline,
        resolver: MediaResolver,
        resolveTimeline: @escaping @Sendable (String) -> Timeline?,
        format: ExportFormat,
        resolution: ExportResolution,
        fcpxmlVersion: FCPXMLVersion = .default,
        fcpxmlTarget: FCPXMLTarget = .default,
        missingMediaRefs: Set<String>,
        outputURL: URL,
        source: ExportJobSource,
        projectID: String,
        analyticsProjectID: String?,
        warnings: [String] = []
    ) throws -> ExportQueueSubmission {
        let resolver = resolver.snapshot()
        // 时间线在这里，别处没有 —— 统计要在入队时算好带下去。
        let clips = timeline.tracks.flatMap(\.clips)
        let fps = Double(max(timeline.fps, 1))
        let stats = FilmExportStats(
            shots: clips.count,
            // 帧转秒只在这里做一次。**时间线的真源是帧**，秒只是上报口径 ——
            // 别处再算一遍就会因为 fps 取错而对不上。
            seconds: Double(clips.map { $0.startFrame + $0.durationFrames }.max() ?? 0) / fps,
            metag: clips.contains { resolver.isGenerated($0.mediaRef) }
        )
        let analyticsInput = ExportTimelineAnalyticsInput(
            scope: .exportedTimeline(root: timeline, resolveTimeline: resolveTimeline),
            manifest: resolver.manifestSnapshot(),
            exportFilename: outputURL.lastPathComponent
        )
        return try enqueue(outputURL: outputURL, projectID: projectID, source: source,
                           warnings: warnings, stats: stats) { service in
            await service.export(
                timeline: timeline,
                resolver: resolver,
                resolveTimeline: resolveTimeline,
                format: format,
                resolution: resolution,
                fcpxmlVersion: fcpxmlVersion,
                fcpxmlTarget: fcpxmlTarget,
                missingMediaRefs: missingMediaRefs,
                outputURL: outputURL,
                analyticsContext: ExportAnalyticsContext(
                    source: source.rawValue,
                    projectId: analyticsProjectID,
                    timelineInput: analyticsInput
                )
            )
        }
    }

    @discardableResult
    func enqueuePalmierProject(
        projectFile: ProjectFile,
        manifest: MediaManifest,
        sourceProjectURL: URL?,
        outputURL: URL,
        source: ExportJobSource,
        projectID: String,
        analyticsProjectID: String?
    ) throws -> ExportQueueSubmission {
        let analyticsInput = ExportTimelineAnalyticsInput(
            scope: .project(
                timelines: projectFile.timelines,
                rootTimelineId: projectFile.activeTimelineId
            ),
            manifest: manifest,
            exportFilename: outputURL.lastPathComponent
        )
        return try enqueue(outputURL: outputURL, projectID: projectID, source: source) { service in
            await service.exportPalmierProject(
                projectFile: projectFile,
                manifest: manifest,
                sourceProjectURL: sourceProjectURL,
                outputURL: outputURL,
                analyticsContext: ExportAnalyticsContext(
                    source: source.rawValue,
                    projectId: analyticsProjectID,
                    timelineInput: analyticsInput
                )
            )
        }
    }

    @discardableResult
    func cancel(_ id: UUID) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return false }
        switch jobs[index].status {
        case .waiting:
            operations[id] = nil
            jobs[index].status = .canceled
            return true
        case .preparing, .exporting:
            if let activeService, !activeService.cancel() { return false }
            jobs[index].status = .canceling
            activeTask?.cancel()
            return true
        case .canceling:
            return true
        default:
            return false
        }
    }

    func remove(_ id: UUID) {
        guard jobs.first(where: { $0.id == id })?.status.isFinished == true else { return }
        jobs.removeAll { $0.id == id }
    }

    func clearFinished(for projectID: String) {
        jobs.removeAll { $0.projectID == projectID && $0.status.isFinished }
    }

#if DEBUG
    @discardableResult
    func enqueueForTesting(
        outputURL: URL,
        projectID: String = "test-project",
        operation: @escaping Operation
    ) throws -> ExportQueueSubmission {
        try enqueue(outputURL: outputURL, projectID: projectID, source: .manual, operation: operation)
    }
#endif

    private func enqueue(
        outputURL: URL,
        projectID: String,
        source: ExportJobSource,
        warnings: [String] = [],
        stats: FilmExportStats? = nil,
        operation: @escaping Operation
    ) throws -> ExportQueueSubmission {
        guard !isDestinationReserved(outputURL) else {
            throw ExportQueueError.destinationInUse(outputURL.lastPathComponent)
        }

        let id = UUID()
        jobs.append(ExportJob(
            id: id,
            projectID: projectID,
            filename: outputURL.lastPathComponent,
            source: source,
            outputURL: outputURL,
            createdAt: .now,
            status: .waiting,
            progress: 0,
            warnings: warnings,
            palmierReport: nil,
            stats: stats
        ))
        operations[id] = operation
        startNext()

        let waiting = jobs.filter { $0.status == .waiting }
        return ExportQueueSubmission(
            jobID: id,
            started: activeID == id,
            queuePosition: waiting.firstIndex(where: { $0.id == id }).map { $0 + 1 } ?? 0
        )
    }

    private func startNext() {
        guard activeID == nil,
              let index = jobs.firstIndex(where: { $0.status == .waiting && operations[$0.id] != nil }) else { return }
        let id = jobs[index].id
        activeID = id
        jobs[index].status = .preparing
        activeTask = Task { @MainActor [weak self] in await self?.run(id) }
    }

    private func run(_ id: UUID) async {
        guard activeID == id, let operation = operations[id] else { return }
        let service = ExportService()
        activeService = service
        guard !Task.isCancelled else {
            finish(id, status: .canceled, service: service)
            return
        }
        service.onPhaseChange = { [weak self] phase in self?.update(phase, for: id) }
        service.onProgressChange = { [weak self] progress in self?.update(progress, for: id) }

        await operation(service)

        let status: ExportJobStatus
        if service.didCommitOutput {
            status = .completed
        } else if service.wasCancelled || job(id)?.status == .canceling {
            status = .canceled
        } else if service.error != nil {
            status = .failed
        } else {
            // 裸英文字面量，而它会进系统通知和导出面板 —— 中文用户读不懂。
            service.error = L10n.string("The export finished but produced no file.")
            status = .failed
        }
        let source = job(id)?.source
        let filename = job(id)?.filename
        let outputURL = job(id)?.outputURL
        finish(id, status: status, service: service)

        // **失败必须出声，不管是谁发起的。**
        //
        // 上一版这里是 `guard source == .agent` —— **人手点的导出不发通知**。
        // 而标题栏那个唯一的全局指示器只在 `status.isRunning` 时闪一个点，
        // `.failed` 没有任何呈现；错误文字只活在 `ExportJob.error` 里，
        // 只有重新打开导出面板才看得见。
        //
        // 于是：⌘E → 选保存位置 → 关掉面板去干别的 → 十分钟后那个点停了
        // （**和导完一模一样**）→ 去 Finder，没有文件，也不知道为什么。
        //
        // 导出成功是团队量"他愿不愿意留着它"的唯一那一格，
        // **而这条路上的失败态此前是全静默的。**
        guard let filename, let outputURL else { return }
        if status == .failed {
            AppNotifications.exportFailed(
                name: filename,
                reason: service.error ?? L10n.string("The export didn't finish.")
            )
        } else if status == .completed, source == .keepIt {
            // **他不知道片子去了哪。** 「留下它」没问他存哪儿（那一刻他要的是
            // "别弄丢它"，不是"决定它叫什么"），所以存完必须让他看见位置 ——
            // 否则这颗按钮的回执是"什么都没发生"。
            NSWorkspace.shared.activateFileViewerSelecting([outputURL])
        } else if status == .completed, source == .agent {
            // 成功那一条仍然只给 agent 发 —— 人手点的时候他就在屏幕前，
            // 而 Finder 里多一个文件本身就是回执。
            AppNotifications.exportComplete(
                name: filename,
                outputURL: outputURL,
                size: service.lastReport?.outputSize,
                warningCount: job(id)?.warningCount(service.lastReport) ?? 0
            )
        }
    }

    private func finish(_ id: UUID, status: ExportJobStatus, service: ExportService) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        // 导出成功是**唯一能说明产品交付了价值**的信号，而我们此前在 Mac 上
        // 完全看不到它（Web 端已经在报）。放在 finish 里而不是那段
        // `guard source == .agent` 之后 —— 那段只覆盖 agent 发起的导出，
        // 而人手动导出的才是大多数。
        if status == .completed {
            // **唯一一个问"他愿不愿意留着它"的那一格。** 其余每一格问的都是
            // "他有没有走完流程"。不记文件名、不记内容。
            MetagFunnel.track(.exported, meta: [
                "where": jobs[index].source.rawValue,
                "fmt": jobs[index].outputURL.pathExtension.lowercased(),
            ])
        }
        if status == .completed, let stats = jobs[index].stats {
            MetagGateway.filmEvent(kind: "export", shots: stats.shots,
                                   seconds: stats.seconds, metag: stats.metag)
        }
        jobs[index].status = status
        jobs[index].progress = status == .completed ? 1 : service.progress
        jobs[index].error = service.error
        if let report = service.lastPalmierReport {
            jobs[index].palmierReport = report
            jobs[index].warnings = report.warnings
        }
        operations[id] = nil
        activeID = nil
        activeTask = nil
        activeService = nil
        startNext()
    }

    private func update(_ phase: ExportService.Phase, for id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].status != .canceling else { return }
        jobs[index].status = phase == .preparing ? .preparing : .exporting
    }

    private func update(_ progress: Double, for id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }),
              jobs[index].status.isPending
        else { return }
        jobs[index].progress = min(1, max(0, progress))
    }

    private func job(_ id: UUID) -> ExportJob? {
        jobs.first { $0.id == id }
    }

}

private extension ExportJob {
    func warningCount(_ mediaReport: ExportRunReport?) -> Int {
        if let palmierReport { return palmierReport.missing.count }
        if let mediaReport {
            return mediaReport.offlineMediaRefs.count + mediaReport.unprocessableMediaRefs.count
        }
        return warnings.count
    }
}
