import ServiceManagement
import SwiftUI

struct PanelView: View {
    @Bindable var store: UsageStore
    @State private var showsDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            windows
            pace
            sessions
            footer
        }
        .frame(width: 300)
    }

    // MARK: -

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Tideline")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            if let plan = store.usage?.plan {
                Text(plan.capitalized)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var windows: some View {
        if let usage = store.usage {
            VStack(spacing: 18) {
                if let five = usage.fiveHour { WindowRow(title: "5-hour", window: five) }
                if let seven = usage.sevenDay { WindowRow(title: "7-day", window: seven) }
                if let opus = usage.sevenDayOpus { WindowRow(title: "7-day Opus", window: opus) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        } else {
            unavailable
        }
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.failure == nil ? "Reading your usage…" : "No reading")
                .font(.system(size: 12, weight: .medium))
            if let failure = store.failure {
                Text(failure)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var pace: some View {
        if let projection = store.projection {
            let urgent = projection.exhaustedIn < 1800
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                Text("\(projection.window) full in \(Format.span(projection.exhaustedIn))")
                    .font(.system(size: 11, weight: .medium))
                Text(String(format: "%.2f%%/min", projection.perMinute))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(urgent ? Color.red : Color.orange)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private var sessions: some View {
        Divider().opacity(0.5)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sessions")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(summary)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            if store.sessions.isEmpty {
                Text("Nothing running")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(store.sessions.prefix(6)) { session in
                    SessionRow(session: session)
                }
                if store.sessions.count > 6 {
                    Text("+\(store.sessions.count - 6) more")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 14)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var summary: String {
        let live = store.sessions.count
        let working = store.workingCount
        return working > 0 ? "\(live) live · \(working) working" : "\(live) live"
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            HStack(spacing: 10) {
                Text(footerStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .help(store.failure ?? "")
                Spacer()
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(store.isRefreshing)

                Menu {
                    Toggle("Show percentage", isOn: $store.showsPercentage)
                    Toggle("Open at login", isOn: launchAtLogin)
                    if store.diagnostics != nil {
                        Divider()
                        Button("Copy diagnostics") { copyDiagnostics() }
                    }
                    Divider()
                    Button("Quit Tideline") { NSApplication.shared.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    /// A stale reading is still worth showing, but never without saying it is stale.
    private var footerStatus: String {
        guard let usage = store.usage else { return " " }
        let age = "Updated \(Format.relative(usage.fetchedAt))"
        return store.failure == nil ? age : "\(age) · retrying"
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { wanted in
                try? wanted ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            }
        )
    }

    private func copyDiagnostics() {
        guard let diagnostics = store.diagnostics else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
    }
}

// MARK: -

private struct WindowRow: View {
    let title: String
    let window: Window

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(window.percent.rounded()))")
                    .font(.system(size: 25, weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundStyle(window.level.color)
                + Text("%")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(window.level == .calm ? .secondary : window.level.color)
            }

            Meter(percent: window.percent, level: window.level)

            if let resetsAt = window.resetsAt {
                Text("resets \(Format.clock(resetsAt)) · in \(Format.span(resetsAt.timeIntervalSinceNow))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct Meter: View {
    let percent: Double
    let level: Level

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.09))
                Capsule()
                    .fill(level.color)
                    .frame(width: geometry.size.width * min(1, max(0, percent / 100)))
            }
        }
        .frame(height: 4)
        .animation(.smooth(duration: 0.35), value: percent)
    }
}

private struct SessionRow: View {
    let session: ClaudeSession

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(session.isWorking ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 5, height: 5)
            Text(session.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(Format.tail(session.directory))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
        }
    }
}
