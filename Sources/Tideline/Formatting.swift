import Foundation

enum Format {
    static func span(_ seconds: TimeInterval, short: Bool = false) -> String {
        let s = Int(max(0, seconds))
        let days = s / 86400
        let hours = (s % 86400) / 3600
        let minutes = (s % 3600) / 60
        if days > 0 { return short ? "\(days)d" : "\(days)d \(hours)h" }
        if hours > 0 { return short ? "\(hours)h" : "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }

    static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate(
            date.timeIntervalSinceNow < 20 * 3600 ? "jmm" : "EEE jmm"
        )
        return f.string(from: date)
    }

    static func relative(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 45 { return "just now" }
        return "\(span(elapsed, short: true)) ago"
    }

    static func home(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    static func tail(_ path: String, components: Int = 2) -> String {
        let shortened = home(path)
        let parts = shortened.split(separator: "/").map(String.init)
        guard parts.count > components else { return shortened }
        return "…/" + parts.suffix(components).joined(separator: "/")
    }
}
