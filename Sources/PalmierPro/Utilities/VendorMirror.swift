import Foundation

/// Ordered sources for runtime assets hosted in third-party repos: METAG's R2 mirror first,
/// upstream second, so an upstream deletion cannot take a feature down. Callers must verify
/// each source's bytes against a pinned or published SHA-256 before trusting them.
enum VendorMirror {
    static var base: String {
        ProcessInfo.processInfo.environment["METAG_VENDOR_BASE"]
            ?? "https://s3.metag.ai/metag/vendor"
    }

    /// Set `METAG_VENDOR_MIRROR_DISABLED=1` to exercise the upstream fallback directly.
    static var mirrorEnabled: Bool {
        ProcessInfo.processInfo.environment["METAG_VENDOR_MIRROR_DISABLED"] == nil
    }

    static func sources(mirrorPath: String, upstream: String) -> [URL] {
        var raw: [String] = []
        if mirrorEnabled { raw.append("\(base)/\(mirrorPath)") }
        raw.append(upstream)

        var seen = Set<String>()
        return raw.compactMap { candidate in
            guard seen.insert(candidate).inserted else { return nil }
            return URL(string: candidate)
        }
    }
}
