import Foundation

/// Direction of a multi-finger swipe, in trackpad-natural orientation:
/// `.up` means fingers moved toward the top edge of the pad.
enum SwipeDirection: String, Codable, CaseIterable, Hashable {
    case up, down, left, right

    var symbol: String {
        switch self {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        }
    }

    var label: String { rawValue.capitalized }
}

enum GestureKind: String, Codable, Hashable {
    case swipe
    case tap
}

/// A discrete, recognizable trackpad gesture. The `id` is stable and used as the
/// persistence key for its binding.
struct Gesture: Codable, Hashable, Identifiable {
    var kind: GestureKind
    var fingers: Int
    /// Only meaningful for `.swipe`.
    var direction: SwipeDirection?

    var id: String {
        switch kind {
        case .swipe: return "swipe-\(fingers)-\(direction?.rawValue ?? "none")"
        case .tap: return "tap-\(fingers)"
        }
    }

    var displayName: String {
        switch kind {
        case .swipe: return "\(fingers)-finger swipe \(direction?.label.lowercased() ?? "")"
        case .tap: return "\(fingers)-finger tap"
        }
    }

    static func swipe(_ fingers: Int, _ direction: SwipeDirection) -> Gesture {
        Gesture(kind: .swipe, fingers: fingers, direction: direction)
    }

    static func tap(_ fingers: Int) -> Gesture {
        Gesture(kind: .tap, fingers: fingers, direction: nil)
    }

    /// The full set of gestures the app exposes for binding.
    /// Limited to 3–5 fingers: 1–2 finger touches are owned by the OS
    /// (pointing, scrolling, secondary click) and aren't safe to remap.
    static let all: [Gesture] = {
        var result: [Gesture] = []
        for fingers in 3...5 {
            for dir in SwipeDirection.allCases {
                result.append(.swipe(fingers, dir))
            }
        }
        for fingers in 3...5 {
            result.append(.tap(fingers))
        }
        return result
    }()

    /// macOS reserves these by default in System Settings ▸ Trackpad; binding them
    /// will fire alongside the system action unless the user disables it there.
    var conflictsWithSystemDefault: Bool {
        switch kind {
        case .swipe:
            // 3- and 4-finger swipes drive Mission Control / spaces / app exposé.
            return fingers == 3 || fingers == 4
        case .tap:
            // 3-finger tap = look up / data detectors (when enabled).
            return fingers == 3
        }
    }
}
