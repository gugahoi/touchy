import AppKit
import CoreGraphics

enum MouseButton: String, Codable, Hashable, CaseIterable {
    case left, right, middle

    var cgButton: CGMouseButton {
        switch self {
        case .left: return .left
        case .right: return .right
        case .middle: return .center
        }
    }

    var eventTypes: (down: CGEventType, up: CGEventType) {
        switch self {
        case .left: return (.leftMouseDown, .leftMouseUp)
        case .right: return (.rightMouseDown, .rightMouseUp)
        case .middle: return (.otherMouseDown, .otherMouseUp)
        }
    }

    var label: String {
        switch self {
        case .left: return "Left Click"
        case .right: return "Right Click"
        case .middle: return "Middle Click"
        }
    }

    var shortLabel: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .middle: return "Middle"
        }
    }
}

/// A synthesized mouse click (with optional modifiers) performed at the current
/// pointer location. `clickCount` is 1 for a single click, 2 for a double-click.
struct MouseClick: Hashable {
    var button: MouseButton
    var command: Bool = false
    var option: Bool = false
    var control: Bool = false
    var shift: Bool = false
    var clickCount: Int = 1

    var cgFlags: CGEventFlags {
        var f: CGEventFlags = []
        if command { f.insert(.maskCommand) }
        if option { f.insert(.maskAlternate) }
        if control { f.insert(.maskControl) }
        if shift { f.insert(.maskShift) }
        return f
    }

    var display: String {
        var s = ""
        if control { s += "⌃" }
        if option { s += "⌥" }
        if shift { s += "⇧" }
        if command { s += "⌘" }
        if !s.isEmpty { s += " " }
        if clickCount >= 2 { s += "Double " }
        return s + button.label
    }
}

extension MouseClick: Codable {
    private enum CodingKeys: String, CodingKey {
        case button, command, option, control, shift, clickCount
    }

    // Custom decode so older entries saved without `clickCount` still load
    // (default 1) instead of throwing — which would silently drop the binding.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        button = try c.decode(MouseButton.self, forKey: .button)
        command = try c.decodeIfPresent(Bool.self, forKey: .command) ?? false
        option = try c.decodeIfPresent(Bool.self, forKey: .option) ?? false
        control = try c.decodeIfPresent(Bool.self, forKey: .control) ?? false
        shift = try c.decodeIfPresent(Bool.self, forKey: .shift) ?? false
        clickCount = try c.decodeIfPresent(Int.self, forKey: .clickCount) ?? 1
    }
}

/// The action bound to a gesture: either a keyboard shortcut or a mouse click.
enum GestureAction: Codable, Hashable {
    case key(KeyCombo)
    case click(MouseClick)

    /// Display string. NOTE: the `.key` case calls Text Input Source APIs
    /// (main-thread only) — call this on the main thread.
    var display: String {
        switch self {
        case .key(let k): return k.display
        case .click(let c): return c.display
        }
    }

    private enum CodingKeys: String, CodingKey { case type, key, click }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // New tagged format: {"type":"key"|"click", ...}
        if let type = try container.decodeIfPresent(String.self, forKey: .type) {
            switch type {
            case "click":
                self = .click(try container.decode(MouseClick.self, forKey: .click))
            default:
                self = .key(try container.decode(KeyCombo.self, forKey: .key))
            }
            return
        }
        // Legacy format: a bare KeyCombo dict ({"keyCode":…,"command":…}).
        self = .key(try KeyCombo(from: decoder))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .key(let k):
            try container.encode("key", forKey: .type)
            try container.encode(k, forKey: .key)
        case .click(let c):
            try container.encode("click", forKey: .type)
            try container.encode(c, forKey: .click)
        }
    }
}
