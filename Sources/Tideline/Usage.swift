import Foundation

struct Window: Equatable, Codable {
    let percent: Double
    let resetsAt: Date?

    var level: Level { Level(percent: percent) }
}

struct Usage: Equatable, Codable {
    var fiveHour: Window?
    var sevenDay: Window?
    var sevenDayOpus: Window?
    var plan: String?
    var fetchedAt: Date = Date()

    /// The ring in the menu bar answers one question — how close am I to being cut off —
    /// so it tracks whichever window is furthest along, not a fixed one.
    var headline: Window? {
        [fiveHour, sevenDay, sevenDayOpus]
            .compactMap { $0 }
            .max { $0.percent < $1.percent }
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
        usage.sevenDayOpus = window(root["seven_day_opus"])

        guard usage.fiveHour != nil || usage.sevenDay != nil else { return nil }
        return usage
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
