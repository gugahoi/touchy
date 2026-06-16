import Foundation
import ServiceManagement

/// Launch-at-login backed by `SMAppService.mainApp` (macOS 13+). Registers the
/// running `.app` bundle as a login item; the system lists it under
/// System Settings ▸ General ▸ Login Items.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns true on success. On failure (e.g. running an unbundled binary),
    /// logs and returns false so the UI can revert the toggle.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            NSLog("Touchy: login item toggle failed: \(error.localizedDescription)")
            return false
        }
    }
}
