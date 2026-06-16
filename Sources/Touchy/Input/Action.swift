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
}

/// A synthesized mouse click (with optional modifiers) performed at the current
/// pointer location.
struct MouseClick: Codable, Hashable {
    var button: MouseButton
    var command: Bool = false
    var option: Bool = false
    var control: Bool = false
    var shift: Bool = false

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
        return s + button.label
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
