import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar agent: no Dock icon. (Also set via LSUIElement in Info.plist.)
        NSApp.setActivationPolicy(.accessory)

        // Begin reading the trackpad and routing gestures to key emission.
        GestureEngine.shared.start()

        if ProcessInfo.processInfo.environment["TOUCHY_DEBUG"] != nil {
            FileHandle.standardError.write(
                Data("[touchy] accessibility trusted = \(Permissions.hasAccessibility)\n".utf8))
        }

        // Nudge the user toward granting Accessibility on first launch if missing.
        if !Permissions.hasAccessibility {
            Permissions.promptForAccessibility()
        }
    }
}
