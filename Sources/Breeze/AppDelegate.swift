import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as menu bar accessory app (hidden from Dock, visible in status bar)
        NSApp.setActivationPolicy(.accessory)

        // Register safety signal handlers to ensure fans always revert to System mode
        signal(SIGINT) { _ in
            FanManager.shared.shutdown()
            exit(0)
        }
        signal(SIGTERM) { _ in
            FanManager.shared.shutdown()
            exit(0)
        }
        signal(SIGHUP) { _ in
            FanManager.shared.shutdown()
            exit(0)
        }

        // Initialize status bar controller
        MenuBarController.shared.setup()

        // Initialize telemetry
        FanManager.shared.updateTelemetry()
    }

    func applicationWillTerminate(_ notification: Notification) {
        FanManager.shared.shutdown()
    }
}
