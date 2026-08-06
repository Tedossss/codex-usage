import Foundation

struct Window: Equatable, Codable {
    let percent: Double
    let resetsAt: Date?

    var level: Level { Level(percent: percent) }
}

/// Which window the menu bar tracks. `fullest` is honest about the worst number but moves
/// between windows on its own, so a glance can mean two different things on two days —
/// hence the fixed 5-hour default.
enum TrackedWindow: String, CaseIterable, Identifiable {
    case fiveHour
    case sevenDay
    case fullest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fiveHour: return "5-hour window"
        case .sevenDay: return "7-day window"
        case .fullest: return "Whichever is fullest"
        }
    }
}

/// A weekly limit that applies to one model rather than all of them — today that is Fable.
/// The name comes from the server, so a new model needs no code change.
struct ScopedWindow: Equatable, Codable, Identifiable {
    let model: String
    let window: Window

    var id: String { model }
}

struct Usage: Equatable, Codable {
    var fiveHour: Window?
    var sevenDay: Window?
    var scoped: [ScopedWindow] = []
    var plan: String?
    var fetchedAt: Date = Date()

    var fullest: Window? {
        ([fiveHour, sevenDay].compactMap { $0 } + scoped.map(\.window))
            .max { $0.percent < $1.percent }
    }

    /// Falls back to the fullest window when the chosen one is not reported, so the menu
    /// bar shows a number rather than a dash on plans that lack it.
    func window(_ tracked: TrackedWindow) -> Window? {
        switch tracked {
        case .fiveHour: return fiveHour ?? fullest
        case .sevenDay: return sevenDay ?? fullest
        case .fullest: return fullest
        }
    }
}

/// Shape of `GET /api/oauth/usage`:
///
///     { "five_hour":  { "utilization": 18.0, "resets_at": "2026-08-05T13:30:00.191297+00:00" },
///       "seven_day":  { "utilization": 20.0, "resets_at": "…" },
///       "seven_day_opus": null,
///       "limits": [ { "kind": "session", "percent": 18, "resets_at": "…" }, … ] }
///
/// `utilization` is already 0–100. The named objects and the `limits` array carry the same
/// numbers, so the array is only consulted where a named object is missing.
enum UsageReader {
    static func parse(_ data: Data) -> Usage? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let byKind = Dictionary(
            (root["limits"] as? [[String: Any]] ?? []).compactMap { entry -> (String, Window)? in
                guard let kind = entry["kind"] as? String,
                      let percent = (entry["percent"] as? NSNumber)?.doubleValue
                else { return nil }
                return (kind, Window(percent: percent, resetsAt: date(entry["resets_at"])))
            },
            uniquingKeysWith: { first, _ in first }
        )

        var usage = Usage()
        usage.fiveHour = window(root["five_hour"]) ?? byKind["session"]
        usage.sevenDay = window(root["seven_day"]) ?? byKind["weekly_all"]
        usage.scoped = scopedWindows(in: root)

        guard usage.fiveHour != nil || usage.sevenDay != nil else { return nil }
        return usage
    }

    private static func scopedWindows(in root: [String: Any]) -> [ScopedWindow] {
        (root["limits"] as? [[String: Any]] ?? []).compactMap { entry in
            guard
                entry["kind"] as? String == "weekly_scoped",
                let percent = (entry["percent"] as? NSNumber)?.doubleValue,
                let scope = entry["scope"] as? [String: Any],
                let model = (scope["model"] as? [String: Any])?["display_name"] as? String
            else { return nil }
            return ScopedWindow(
                model: model,
                window: Window(percent: percent, resetsAt: date(entry["resets_at"]))
            )
        }
    }

    private static func window(_ node: Any?) -> Window? {
        guard let node = node as? [String: Any],
              let utilization = (node["utilization"] as? NSNumber)?.doubleValue
        else { return nil }
        return Window(percent: utilization, resetsAt: date(node["resets_at"]))
    }

    /// Timestamps carry microseconds, which the default ISO-8601 reader rejects outright.
    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        for options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]]
            as [ISO8601DateFormatter.Options]
        {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}
