import Foundation

public actor TranscriptDiscovery {
    public init() {}

    /// Returns session ids (filename stems) for `*.jsonl` files under
    /// `<root>/<project-dir>/<session-id>.jsonl` whose modification date is
    /// newer than `cutoff`, sorted most-recent first, capped at `limit`.
    public func findRecentSessionIDs(root: URL, cutoff: Date, limit: Int) async throws -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }

        struct Candidate {
            let id: String
            let mtime: Date
        }
        var candidates: [Candidate] = []

        // Each subdirectory under root is a project. We only descend one level.
        let projects = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for project in projects {
            let isDir = (try? project.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            let files = (try? fm.contentsOfDirectory(at: project, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files where file.pathExtension == "jsonl" {
                guard let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                      mtime >= cutoff else { continue }
                let id = file.deletingPathExtension().lastPathComponent
                candidates.append(Candidate(id: id, mtime: mtime))
            }
        }

        candidates.sort { $0.mtime > $1.mtime }
        return candidates.prefix(limit).map(\.id)
    }

    /// Default Claude Code transcript root: `~/.claude/projects`.
    public static func defaultClaudeRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }
}
