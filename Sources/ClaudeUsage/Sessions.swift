import Darwin
import Foundation

struct ClaudeSession: Equatable {
    let pid: Int32
    let isWorking: Bool
}

enum SessionScanner {
    static var directory: URL {
        let override = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
        let root = override.map(URL.init(fileURLWithPath:))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        return root.appendingPathComponent("sessions")
    }

    /// Claude Code leaves one JSON per session behind, named by pid, and the files outlive
    /// their processes. A live pid is not enough either — pids get recycled — so the
    /// executable behind it has to still be a Claude CLI.
    static func scan(maxAge: TimeInterval = 30 * 86400) -> [ClaudeSession] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }

        let cutoff = Date().addingTimeInterval(-maxAge)
        var found: [ClaudeSession] = []

        for file in files where file.pathExtension == "json" {
            guard
                let data = try? Data(contentsOf: file),
                let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let pid = (raw["pid"] as? NSNumber)?.int32Value,
                let millis = (raw["updatedAt"] as? NSNumber)?.doubleValue
            else { continue }

            let updated = Date(timeIntervalSince1970: millis / 1000)
            guard updated > cutoff, isClaudeCLI(pid) else { continue }

            found.append(
                ClaudeSession(pid: pid, isWorking: raw["status"] as? String == "busy")
            )
        }
        return found.sorted { $0.pid < $1.pid }
    }

    /// `proc_name` is useless here: Claude Code's executable is named after its version
    /// (`~/.local/share/claude/versions/2.1.222`), so the process is called "2.1.222" and
    /// never "claude". The full path is what identifies it.
    private static func isClaudeCLI(_ pid: Int32) -> Bool {
        var buffer = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        let path = String(cString: buffer)
        return path.contains("claude") && !path.contains("/Claude.app/")
    }
}
