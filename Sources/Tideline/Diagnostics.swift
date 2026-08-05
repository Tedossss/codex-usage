import Foundation

/// `/api/oauth/usage` is undocumented, so the last raw exchange is kept on disk. It is the
/// only way to tell "the parser is wrong" apart from "the account has no limits".
enum Diagnostics {
    static var directory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tideline", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var lastResponseURL: URL { directory.appendingPathComponent("last-response.json") }

    static func record(status: Int, body: String) {
        let stamped = """
            // HTTP \(status) at \(ISO8601DateFormatter().string(from: Date()))
            \(body)
            """
        try? stamped.write(to: lastResponseURL, atomically: true, encoding: .utf8)
    }
}
