import CryptoKit
import Foundation
import Testing
@testable import PalmierPro

@Suite("ModelDownloader — mirror/upstream fallback")
struct ModelSourceFallbackTests {
    private func makeBase(_ root: URL, name: String, contents: Data) throws -> URL {
        let dir = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try contents.write(to: dir.appendingPathComponent(name))
        return dir
    }

    @Test func fallsBackToNextSourceWhenTheFirstServesCorruptBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let good = Data("the real model bytes".utf8)
        let name = "Encoder.zip"
        let file = ModelDownloader.Manifest.File(
            name: name,
            sha256: SHA256.hash(data: good).map { String(format: "%02x", $0) }.joined(),
            bytes: Int64(good.count)
        )

        let corruptBase = try makeBase(root, name: name, contents: Data("tampered".utf8))
        let goodBase = try makeBase(root, name: name, contents: good)
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let result = try await ModelDownloader().downloadVerified(
            file, from: [corruptBase, goodBase], to: staging, progress: { _ in }
        )

        #expect(try Data(contentsOf: result) == good)
    }

    @Test func throwsWhenEverySourceFailsVerification() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let name = "Encoder.zip"
        let file = ModelDownloader.Manifest.File(
            name: name, sha256: String(repeating: "0", count: 64), bytes: 8
        )
        let a = try makeBase(root, name: name, contents: Data("aaaa".utf8))
        let b = try makeBase(root, name: name, contents: Data("bbbb".utf8))
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        await #expect(throws: ModelDownloader.DownloadError.self) {
            try await ModelDownloader().downloadVerified(
                file, from: [a, b], to: staging, progress: { _ in }
            )
        }
    }
}
