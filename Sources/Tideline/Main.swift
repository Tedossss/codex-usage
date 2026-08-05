import AppKit

// A SwiftUI `App` whose only scene is `Settings` never finishes launching as an agent app:
// `applicationDidFinishLaunching` never fires, so no status item is ever created. The AppKit
// entry point does not depend on there being a window to show.
@main
@MainActor
enum Main {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}
