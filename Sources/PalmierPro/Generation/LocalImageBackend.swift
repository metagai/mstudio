import Foundation

/// On-device image generation via `sd-cli`. No network, no credits, no provider review.
///
/// One process per image rather than a resident server: measured 2026-08-31 on M3/16GB,
/// a resident `sd-server` went 142s → 180s → SIGKILL while separate processes held at
/// 12.2 → 13.9 s/step. The ~60s reload per image buys surviving the third click.
enum LocalImageBackend {
    static let modelId = "local-z-image"

    /// Probe layout for now; a real installer into Application Support comes later.
    static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".metag-probe")

    private static var binary: URL { root.appendingPathComponent("sdcpp/build/bin/sd-cli") }
    private static var models: URL { root.appendingPathComponent("models") }

    /// Q6_K is the chosen tier: Q3_K is 50s faster but visibly coarser. In-frame text is
    /// garbled at every tier — that is the 832×480 canvas, not the quantization.
    private static let diffusionModel = "z_image_turbo-Q6_K.gguf"
    private static let textEncoder = "Qwen3-4B-Instruct-2507-Q4_K_M.gguf"
    private static let vae = "ae.safetensors"

    /// Eight steps is a product decision, not a tuning knob: four steps distorts hands.
    private static let steps = 8

    static let defaultWidth = 832
    static let defaultHeight = 480

    struct Missing: LocalizedError {
        let what: String
        var errorDescription: String? {
            L10n.key("Local generation is not set up yet, missing:") + " \(what)"
        }
    }

    struct Failed: LocalizedError {
        let reason: String
        var errorDescription: String? {
            L10n.key("Local generation failed:") + " \(reason)"
        }
    }

    /// Names the missing piece rather than reporting a bare "unavailable".
    @concurrent
    static func check() async throws {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: binary.path) else { throw Missing(what: "sd-cli") }
        for f in [diffusionModel, textEncoder, vae]
        where !fm.fileExists(atPath: models.appendingPathComponent(f).path) {
            throw Missing(what: f)
        }
    }

    @concurrent
    static func isAvailable() async -> Bool {
        do { try await check(); return true } catch { return false }
    }

    /// Minutes, not seconds — p50 184s on M3/16GB. Callers must show progress.
    @concurrent
    static func generate(
        prompt: String,
        width: Int = defaultWidth,
        height: Int = defaultHeight,
        seed: Int? = nil,
        onStep: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> URL {
        try await check()

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("metag-local-\(UUID().uuidString).png")

        let process = Process()
        process.executableURL = binary
        process.arguments = [
            "--diffusion-model", models.appendingPathComponent(diffusionModel).path,
            "--vae", models.appendingPathComponent(vae).path,
            "--llm", models.appendingPathComponent(textEncoder).path,
            "-p", prompt,
            // Turbo is guidance-free distilled; raising cfg only costs time and quality.
            "--cfg-scale", "1.0",
            "--steps", String(steps),
            "-W", String(width), "-H", String(height),
            // Without this, Metal OOMs: it keeps weights in pageable RAM, streamed on demand.
            "--offload-to-cpu",
            "--diffusion-fa",
            "-o", out.path,
        ]
        if let seed { process.arguments?.append(contentsOf: ["--seed", String(seed)]) }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let tail = OutputTail()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            tail.append(text)
            for match in text.matches(of: /(\d+)\/(\d+) - [\d.]+s\/it/) {
                if let done = Int(match.1), let total = Int(match.2) { onStep?(done, total) }
            }
        }

        defer { pipe.fileHandleForReading.readabilityHandler = nil }

        try await withTaskCancellationHandler {
            try process.run()
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                process.terminationHandler = { _ in c.resume() }
            }
        } onCancel: {
            process.terminate()
        }

        if Task.isCancelled {
            try? FileManager.default.removeItem(at: out)
            throw CancellationError()
        }

        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: out.path) else {
            try? FileManager.default.removeItem(at: out)
            throw Failed(reason: tail.errorLines(limit: 3)
                         ?? L10n.key("exit code") + " \(process.terminationStatus)")
        }
        return out
    }
}

/// `readabilityHandler` fires on an arbitrary thread, so the tail needs its own lock.
private final class OutputTail: @unchecked Sendable {
    private var buffer = ""
    private let lock = NSLock()

    func append(_ text: String) {
        lock.lock()
        buffer = String((buffer + text).suffix(4000))
        lock.unlock()
    }

    /// Progress bars dominate the output; only the error lines are worth showing a user.
    func errorLines(limit: Int) -> String? {
        lock.lock()
        let snapshot = buffer
        lock.unlock()
        let lines = snapshot.split(separator: "\n")
            .filter { $0.localizedCaseInsensitiveContains("error") }
            .suffix(limit)
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
