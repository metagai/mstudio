import Foundation

/// One entry in the published catalog.json. `sha` is a content hash of the SKILL.md
/// and is the version anchor: a changed sha means an update is available.
struct SkillCatalogEntry: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let sha: String
    let path: String
}

/// Fetches the community skill catalog from the palmier-skills repo (raw GitHub CDN)
@Observable
@MainActor
final class SkillCatalog {
    static let shared = SkillCatalog()

    /// Upstream source. Third-party repo: the fallback, not the primary.
    static let upstreamBase = "https://raw.githubusercontent.com/palmier-io/palmier-skills/main"
    /// Path of the METAG mirror under `VendorMirror.base`.
    static let mirrorPath = "palmier-skills/main"

    /// Ordered catalog sources: METAG mirror first, upstream second.
    /// Override with the PALMIER_SKILLS_BASE env var to pin a single source, e.g. a local
    /// clone at file:///path/to/palmier-skills.
    static var bases: [String] {
        if let pinned = ProcessInfo.processInfo.environment["PALMIER_SKILLS_BASE"] { return [pinned] }
        return VendorMirror.sources(mirrorPath: mirrorPath, upstream: upstreamBase)
            .map(\.absoluteString)
    }

    private(set) var entries: [SkillCatalogEntry] = []
    private(set) var isLoading = false
    private(set) var lastError: String?

    private static var cacheURL: URL {
        DiskCache.rootDirectory.appendingPathComponent("skills-catalog.json")
    }

    private init() { loadCache() }

    func entry(id: String) -> SkillCatalogEntry? { entries.first { $0.id == id } }

    /// Ordered body sources for one skill, mirror first.
    static func bodyURLs(path: String) -> [URL] { bases.compactMap { URL(string: "\($0)/\(path)") } }

    private func loadCache() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let decoded = try? JSONDecoder().decode([SkillCatalogEntry].self, from: data)
        else { return }
        entries = decoded
    }

    @discardableResult
    func refresh() async -> Bool {
        guard !isLoading else { return false }
        isLoading = true
        defer { isLoading = false }

        var lastError: Error?
        for base in Self.bases {
            guard let url = URL(string: "\(base)/catalog.json") else { continue }
            do {
                let data = try await Self.fetch(url)
                let decoded = try JSONDecoder().decode([SkillCatalogEntry].self, from: data)
                entries = decoded
                self.lastError = nil
                try? FileManager.default.createDirectory(
                    at: Self.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try? data.write(to: Self.cacheURL)
                Log.agent.notice("skill catalog loaded \(decoded.count) entries from \(base)")
                return true
            } catch {
                lastError = error
                Log.agent.error("skill catalog refresh failed (\(base)): \(error.localizedDescription)")
            }
        }
        self.lastError = lastError?.localizedDescription ?? "no catalog source available"
        return false
    }

    /// Bounded so an unreachable mirror fails over to upstream in seconds, not on the 60s default.
    static let requestTimeout: TimeInterval = 10

    /// Reads a catalog/body URL. File URLs are read directly
    static func fetch(_ url: URL) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
