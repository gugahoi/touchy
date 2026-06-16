import AppKit
import CoreGraphics

/// Synthesizes keyboard shortcuts via Quartz event services.
/// Requires Accessibility permission (System Settings ▸ Privacy & Security ▸ Accessibility).
enum KeyEmitter {
    /// Posts a key-down then key-up for the combo, with modifier flags applied to
    /// both events so the receiving app sees a real chord.
    static func post(_ combo: KeyCombo) {
        let source = CGEventSource(stateID: .combinedSessionState)

        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: false)
        else { return }

        down.flags = combo.cgFlags
        up.flags = combo.cgFlags

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
