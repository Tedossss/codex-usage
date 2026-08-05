import AppKit
import SwiftUI

/// SwiftUI's MenuBarExtra never materialised a status item on this system, so the bar item
/// is built with AppKit directly. It also lets the button image be set from a plain NSImage
/// instead of round-tripping through a SwiftUI view.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var monitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.imagePosition = .imageOnly
        statusItem = item

        popover.behavior = .transient
        popover.animates = true
        let controller = NSHostingController(rootView: PanelView(store: store))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller

        store.onUpdate = { [weak self] in self?.redraw() }
        redraw()

        // `defaults write com.vasfal.tideline autoShowPanel -bool true` opens the panel a few
        // seconds after launch, so the layout can be screenshotted without a human click.
        if UserDefaults.standard.bool(forKey: "autoShowPanel") {
            Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    NSApp.activate(ignoringOtherApps: true)
                    self?.toggle()
                }
            }
        }
    }

    private func redraw() {
        statusItem?.button?.image = store.menuBarImage
    }

    @objc private func toggle() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        store.refreshSessions()
        Task { await store.refresh() }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
