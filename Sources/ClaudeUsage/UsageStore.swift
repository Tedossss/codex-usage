import Observation
import SwiftUI

@Observable
@MainActor
final class UsageStore {
    private(set) var usage: Usage?
    private(set) var sessions: [ClaudeSession] = []
    private(set) var failure: String?
    private(set) var diagnostics: String?
    private(set) var isRefreshing = false

    private static let percentageKey = "showsPercentage"
    private static let trackedKey = "trackedWindow"

    /// Seeded from its declaration rather than assigned in `init`: `@Observable` rewrites
    /// stored properties into accessors, so an assignment in the initialiser would fire
    /// `didSet` and write the preference back on every launch.
    var showsPercentage: Bool = UserDefaults.standard.object(forKey: percentageKey) as? Bool
        ?? true
    {
        didSet {
            UserDefaults.standard.set(showsPercentage, forKey: Self.percentageKey)
            onUpdate?()
        }
    }

    var trackedWindow: TrackedWindow =
        UserDefaults.standard.string(forKey: trackedKey).flatMap(TrackedWindow.init) ?? .fiveHour
    {
        didSet {
            UserDefaults.standard.set(trackedWindow.rawValue, forKey: Self.trackedKey)
            onUpdate?()
        }
    }

    /// The status item is AppKit, so it is told to redraw rather than observing.
    var onUpdate: (() -> Void)?

    private let api = UsageAPI()
    private let history = History()
    private let cache = UsageCache()
    private var tick: Timer?
    private var sessionTimer: Timer?

    private static let interval: TimeInterval = 120
    private static let maximumBackoff: TimeInterval = 900
    private var backoff: TimeInterval = 0
    private var nextFetch = Date.distantPast

    var projection: Projection? { usage.flatMap(history.projection(for:)) }
    var workingCount: Int { sessions.filter(\.isWorking).count }

    init() {
        usage = cache.load()
        // Relaunching should not cost a request. The endpoint rate limits, and a reading
        // taken a minute ago is still the same reading.
        if let fetchedAt = usage?.fetchedAt {
            nextFetch = fetchedAt.addingTimeInterval(Self.interval)
        }
        refreshSessions()
        Task { await refreshIfDue() }

        tick = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshIfDue() }
        }
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshSessions() }
        }
    }

    func refreshIfDue() async {
        guard Date() >= nextFetch else { return }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let fetched = try await api.fetch()
            usage = fetched
            cache.save(fetched)
            history.record(fetched)
            failure = nil
            diagnostics = nil
            backoff = 0
            nextFetch = Date().addingTimeInterval(Self.interval)
        } catch {
            failure = error.localizedDescription
            diagnostics = (error as? UsageAPIError)?.payload
            // A failed request must not blank a reading that is still broadly true — the
            // windows only move while Claude is being used.
            scheduleRetry(after: error)
        }
        onUpdate?()
    }

    private func scheduleRetry(after error: Error) {
        var delay = max(Self.interval, backoff * 2)
        if case .rateLimited(let retryAfter)? = error as? UsageAPIError {
            delay = max(delay, retryAfter ?? 120)
        }
        backoff = min(delay, Self.maximumBackoff)
        nextFetch = Date().addingTimeInterval(backoff)
    }

    func refreshSessions() {
        let scanned = SessionScanner.scan()
        guard scanned != sessions else { return }
        sessions = scanned
        onUpdate?()
    }

    var menuBarImage: NSImage {
        MenuBarIcon.image(
            percent: usage?.window(trackedWindow)?.percent,
            showsNumber: showsPercentage
        )
    }
}

/// The last good reading, so a relaunch shows a number immediately instead of a dash.
struct UsageCache {
    private var url: URL { Diagnostics.directory.appendingPathComponent("usage.json") }

    func load() -> Usage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Usage.self, from: data)
    }

    func save(_ usage: Usage) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(usage).write(to: url, options: .atomic)
    }
}
