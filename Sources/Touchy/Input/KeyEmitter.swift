import AppKit
import CoreGraphics

/// Synthesizes input events via Quartz event services.
/// Requires Accessibility permission (System Settings ▸ Privacy & Security ▸ Accessibility).
/// All methods are safe to call off the main thread.
enum KeyEmitter {
    static func perform(_ action: GestureAction) {
        switch action {
        case .key(let combo): post(combo)
        case .click(let click): post(click)
        }
    }

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

    /// Posts a mouse click (with modifier flags) at the current pointer location.
    /// For a double-click, posts two down/up pairs with increasing click state so
    /// the receiving app recognizes them as a genuine double-click.
    static func post(_ click: MouseClick) {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Current cursor position in CG global coords (top-left origin). Staying in
        // CGEvent avoids the AppKit coordinate flip.
        let location = CGEvent(source: source)?.location ?? .zero
        let types = click.button.eventTypes
        let count = max(1, click.clickCount)

        for clickState in 1...count {
            guard
                let down = CGEvent(mouseEventSource: source, mouseType: types.down,
                                   mouseCursorPosition: location, mouseButton: click.button.cgButton),
                let up = CGEvent(mouseEventSource: source, mouseType: types.up,
                                 mouseCursorPosition: location, mouseButton: click.button.cgButton)
            else { return }

            down.flags = click.cgFlags
            up.flags = click.cgFlags
            down.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
            up.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))

            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}
