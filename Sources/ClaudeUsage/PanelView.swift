import ServiceManagement
import SwiftUI

struct PanelView: View {
    @Bindable var store: UsageStore

    private let gutter: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            windows
            pace
            meta
        }
        .frame(width: 292)
    }

    // MARK: -

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let mark = ClaudeMark.shared {
                Image(nsImage: mark)
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 13, height: 13)
                    .foregroundStyle(.secondary)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1.5 }
            }
            Text("Claude Usage")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if let plan = store.usage?.plan {
                Text(plan.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, gutter)
        .padding(.top, 15)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var windows: some View {
        if let usage = store.usage {
            VStack(spacing: 17) {
                if let five = usage.fiveHour { WindowRow(title: "5-hour", window: five) }
                if let seven = usage.sevenDay { WindowRow(title: "7-day", window: seven) }
                if let opus = usage.sevenDayOpus { WindowRow(title: "7-day Opus", window: opus) }
            }
            .padding(.horizontal, gutter)
            .padding(.bottom, 18)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text(store.failure == nil ? "Reading your usage…" : "No reading yet")
                    .font(.system(size: 12, weight: .medium))
                if let failure = store.failure {
                    Text(failure)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, gutter)
            .padding(.bottom, 18)
        }
    }

    @ViewBuilder
    private var pace: some View {
        if let projection = store.projection {
            let urgent = projection.exhaustedIn < 1800
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8.5, weight: .bold))
                Text("\(projection.window) full in \(Format.span(projection.exhaustedIn))")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(String(format: "%.2f%%/min", projection.perMinute))
                    .font(.system(size: 10).monospacedDigit())
                    .opacity(0.7)
            }
            .foregroundStyle(urgent ? Color.red : Color.orange)
            .padding(.horizontal, gutter)
            .padding(.bottom, 18)
        }
    }

    private var meta: some View {
        VStack(spacing: 7) {
            Divider().opacity(0.45)
            HStack {
                Text("Sessions")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                sessionCount
            }
            .padding(.horizontal, gutter)
            .padding(.top, 4)

            HStack(spacing: 12) {
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
                    Picker("Menu bar shows", selection: $store.trackedWindow) {
                        ForEach(TrackedWindow.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Toggle("Show percentage", isOn: $store.showsPercentage)
                    Toggle("Open at login", isOn: launchAtLogin)
                    if store.diagnostics != nil {
                        Divider()
                        Button("Copy diagnostics") { copyDiagnostics() }
                    }
                    Divider()
                    Button("Quit Claude Usage") { NSApplication.shared.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, gutter)
            .padding(.bottom, 11)
        }
    }

    private var sessionCount: some View {
        HStack(spacing: 5) {
            Text("\(store.sessions.count)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
            if store.workingCount > 0 {
                Circle()
                    .fill(Color.green)
                    .frame(width: 4.5, height: 4.5)
                Text("\(store.workingCount) working")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.smooth(duration: 0.3), value: store.workingCount)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(window.percent.rounded()))")
                    .font(.system(size: 19, weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundStyle(window.level.color)
                    .contentTransition(.numericText(value: window.percent))
                    .animation(.smooth(duration: 0.35), value: window.percent)
                Text("%")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 1)
            }

            Meter(percent: window.percent, level: window.level)

            if let resetsAt = window.resetsAt {
                // Two ends of the same fact, sharing the row above's left and right edges.
                HStack {
                    Text("resets \(Format.clock(resetsAt))")
                    Spacer()
                    Text("in \(Format.span(resetsAt.timeIntervalSinceNow))")
                }
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
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(level.color)
                    .frame(width: max(4, geometry.size.width * min(1, max(0, percent / 100))))
            }
        }
        .frame(height: 4)
        .animation(.smooth(duration: 0.4), value: percent)
    }
}
