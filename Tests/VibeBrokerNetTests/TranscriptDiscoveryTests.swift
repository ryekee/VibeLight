import XCTest
@testable import VibeBrokerNet

final class TranscriptDiscoveryTests: XCTestCase {
    private func tempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibelight-disc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func touch(_ url: URL, mtime: Date) throws {
        FileManager.default.createFile(atPath: url.path, contents: Data())
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
    }

    func testFindsRecentSessionIDs() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("-Users-me-projA")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let now = Date()
        try touch(project.appendingPathComponent("abc-123.jsonl"), mtime: now)
        try touch(project.appendingPathComponent("def-456.jsonl"), mtime: now.addingTimeInterval(-60))

        let discovery = TranscriptDiscovery()
        let ids = try await discovery.findRecentSessionIDs(
            root: root, cutoff: now.addingTimeInterval(-3600), limit: 40
        )

        XCTAssertEqual(Set(ids), Set(["abc-123", "def-456"]))
    }

    func testIgnoresFilesOlderThanCutoff() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("-foo")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let now = Date()
        try touch(project.appendingPathComponent("fresh.jsonl"), mtime: now)
        try touch(project.appendingPathComponent("stale.jsonl"), mtime: now.addingTimeInterval(-48 * 3600))

        let discovery = TranscriptDiscovery()
        let ids = try await discovery.findRecentSessionIDs(
            root: root, cutoff: now.addingTimeInterval(-24 * 3600), limit: 40
        )

        XCTAssertEqual(ids, ["fresh"])
    }

    func testRespectsLimit() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("-foo")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let now = Date()
        for i in 0..<10 {
            try touch(project.appendingPathComponent("session-\(i).jsonl"),
                      mtime: now.addingTimeInterval(TimeInterval(-i)))
        }

        let discovery = TranscriptDiscovery()
        let ids = try await discovery.findRecentSessionIDs(
            root: root, cutoff: now.addingTimeInterval(-3600), limit: 3
        )

        XCTAssertEqual(ids.count, 3)
        // Most-recent first: session-0, session-1, session-2.
        XCTAssertEqual(ids, ["session-0", "session-1", "session-2"])
    }

    func testReturnsEmptyWhenRootMissing() async throws {
        let discovery = TranscriptDiscovery()
        let nope = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString)")
        let ids = try await discovery.findRecentSessionIDs(
            root: nope, cutoff: Date().addingTimeInterval(-3600), limit: 40
        )
        XCTAssertTrue(ids.isEmpty)
    }
}
