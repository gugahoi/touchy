import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut to synthesize: a virtual key code plus modifier flags.
struct KeyCombo: Codable, Hashable {
    var keyCode: UInt16
    var command: Bool = false
    var option: Bool = false
    var control: Bool = false
    var shift: Bool = false

    var modifierFlags: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if command { f.insert(.command) }
        if option { f.insert(.option) }
        if control { f.insert(.control) }
        if shift { f.insert(.shift) }
        return f
    }

    var cgFlags: CGEventFlags {
        var f: CGEventFlags = []
        if command { f.insert(.maskCommand) }
        if option { f.insert(.maskAlternate) }
        if control { f.insert(.maskControl) }
        if shift { f.insert(.maskShift) }
        return f
    }

    /// Human-readable form, e.g. "⌘⇧A" or "⌃→".
    var display: String {
        var s = ""
        if control { s += "⌃" }
        if option { s += "⌥" }
        if shift { s += "⇧" }
        if command { s += "⌘" }
        s += KeyCombo.keyName(for: keyCode)
        return s
    }

    static func from(event: NSEvent) -> KeyCombo {
        let m = event.modifierFlags
        return KeyCombo(
            keyCode: UInt16(event.keyCode),
            command: m.contains(.command),
            option: m.contains(.option),
            control: m.contains(.control),
            shift: m.contains(.shift)
        )
    }

    /// Display name for a virtual key code. Covers common special keys; falls back
    /// to the character produced by the key on the current layout.
    static func keyName(for keyCode: UInt16) -> String {
        if let named = specialKeyNames[Int(keyCode)] { return named }
        return layoutCharacter(for: keyCode) ?? "key\(keyCode)"
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
        kVK_Escape: "⎋", kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// Resolve the character a key produces using the active keyboard layout, so
    /// e.g. keyCode 0 shows "A" on QWERTY but the right letter on other layouts.
    private static func layoutCharacter(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = unsafeBitCast(layoutData, to: CFData.self)
        let keyLayoutPtr = CFDataGetBytePtr(data)
        let keyLayout = unsafeBitCast(keyLayoutPtr, to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = UCKeyTranslate(
            keyLayout, keyCode, UInt16(kUCKeyActionDisplay), 0,
            UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState, chars.count, &length, &chars
        )
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
