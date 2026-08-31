import Combine
import Foundation

/// Registry for on-device generations, shaped like a gateway job so `GenerationService`
/// keeps one orchestration path: submit returns an id, the caller subscribes for updates.
@MainActor
enum LocalJobs {
    private static let prefix = "local:"

    private struct Job {
        let subject: CurrentValueSubject<BackendGenerationJob?, Never>
        let task: Task<Void, Never>
    }

    private static var jobs: [String: Job] = [:]

    static func isLocal(_ jobId: String) -> Bool { jobId.hasPrefix(prefix) }

    static func start(prompt: String) -> String {
        let id = prefix + UUID().uuidString
        let subject = CurrentValueSubject<BackendGenerationJob?, Never>(
            snapshot(id, .queued, urls: nil, error: nil)
        )

        let task = Task {
            subject.send(snapshot(id, .running, urls: nil, error: nil))
            do {
                let png = try await LocalImageBackend.generate(prompt: prompt)
                subject.send(snapshot(id, .succeeded, urls: [png.absoluteString], error: nil))
            } catch is CancellationError {
                // A user cancel is not a failure; sending one would paint the UI red.
            } catch {
                subject.send(snapshot(id, .failed, urls: nil, error: error.localizedDescription))
            }
            subject.send(completion: .finished)
            jobs[id] = nil
        }

        jobs[id] = Job(subject: subject, task: task)
        return id
    }

    /// Returns nil for gateway ids so the caller falls through to polling.
    static func subscribe(_ jobId: String) -> AnyPublisher<BackendGenerationJob?, Never>? {
        guard isLocal(jobId) else { return nil }
        // A finished local job is already evicted; an empty stream beats asking the
        // gateway about an id it has never seen.
        guard let job = jobs[jobId] else { return Empty().eraseToAnyPublisher() }
        return job.subject
            .handleEvents(receiveCancel: { Task { @MainActor in cancel(jobId) } })
            .eraseToAnyPublisher()
    }

    static func cancel(_ jobId: String) {
        jobs[jobId]?.task.cancel()
        jobs[jobId] = nil
    }

    private static func snapshot(
        _ id: String,
        _ status: BackendGenerationStatus,
        urls: [String]?,
        error: String?
    ) -> BackendGenerationJob {
        BackendGenerationJob(
            _id: id,
            status: status,
            resultUrls: urls,
            errorMessage: error,
            // Zero rather than nil: nil renders as an unknown cost, and this one is known.
            costCredits: 0,
            refundedCredits: nil,
            completedAt: status == .succeeded ? Date().timeIntervalSince1970 : nil,
            readyCount: status == .succeeded ? 1 : 0
        )
    }
}
