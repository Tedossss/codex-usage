import Foundation

struct Sample: Codable {
    let at: Date
    let fiveHour: Double?
    let sevenDay: Double?
}

struct Projection {
    let window: String
    let perMinute: Double
    let exhaustedIn: TimeInterval
}

/// Keeps a rolling window of usage readings on disk so the projection survives a restart,
/// and throws the history away whenever a limit window rolls over.
final class History {
    private static let span: TimeInterval = 2 * 3600
    private static let minimumSpan: TimeInterval = 240
    private static let minimumPercent: Double = 12

    private let url: URL
    private(set) var samples: [Sample] = []
    private var windowKey: Date?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Claude Usage", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        url = support.appendingPathComponent("history.json")
        load()
    }

    func record(_ usage: Usage) {
        if windowKey != usage.fiveHour?.resetsAt {
            samples = []
            windowKey = usage.fiveHour?.resetsAt
        }
        let now = Date()
        if let last = samples.last, now.timeIntervalSince(last.at) < 30 { return }
        samples.append(
            Sample(at: now, fiveHour: usage.fiveHour?.percent, sevenDay: usage.sevenDay?.percent)
        )
        samples = samples.filter { now.timeIntervalSince($0.at) <= Self.span }.suffix(240)
        save()
    }

    /// The projection is only worth showing when it lands *before* the window would have
    /// reset anyway. Otherwise it is technically true and practically noise.
    func projection(for usage: Usage) -> Projection? {
        let candidates: [(String, KeyPath<Sample, Double?>, Window?)] = [
            ("5-hour", \.fiveHour, usage.fiveHour),
            ("7-day", \.sevenDay, usage.sevenDay),
        ]

        return candidates.compactMap { label, key, window -> Projection? in
            guard let window, window.percent >= Self.minimumPercent, window.percent < 100,
                  let rate = slope(key), rate > 0
            else { return nil }

            let eta = (100 - window.percent) / rate
            if let resetsAt = window.resetsAt {
                let untilReset = resetsAt.timeIntervalSinceNow
                if untilReset > 0, eta >= untilReset { return nil }
            }
            return Projection(window: label, perMinute: rate * 60, exhaustedIn: eta)
        }
        .min { $0.exhaustedIn < $1.exhaustedIn }
    }

    /// Percent per second, least squares over the retained samples.
    private func slope(_ key: KeyPath<Sample, Double?>) -> Double? {
        let points = samples.compactMap { sample -> (Double, Double)? in
            guard let y = sample[keyPath: key] else { return nil }
            return (sample.at.timeIntervalSince1970, y)
        }
        guard points.count >= 3,
              let first = points.first, let last = points.last,
              last.0 - first.0 >= Self.minimumSpan
        else { return nil }

        let n = Double(points.count)
        let meanX = points.reduce(0) { $0 + $1.0 } / n
        let meanY = points.reduce(0) { $0 + $1.1 } / n
        let denominator = points.reduce(0) { $0 + pow($1.0 - meanX, 2) }
        guard denominator > 0 else { return nil }
        return points.reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) } / denominator
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        samples = (try? decoder.decode([Sample].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(samples).write(to: url, options: .atomic)
    }
}
