import Foundation
import Combine

/// Holds gesture→action bindings and the global enable flag, persisted as
/// `bindings.json` (see `ConfigFiles` for where it lives). Observable so the UI
/// updates live; thread-safe reads via a lock so the multitouch callback thread can
/// look up bindings without hopping.
///
/// Legacy `bindings.json` files stored bare `KeyCombo` dicts as values; those
/// decode transparently as `.key` actions (see `GestureAction.init(from:)`).
final class BindingStore: ObservableObject {
    static let shared = BindingStore()

    struct Persisted: Codable {
        var enabled: Bool
        var bindings: [String: GestureAction]

        init(enabled: Bool, bindings: [String: GestureAction]) {
            self.enabled = enabled
            self.bindings = bindings
        }

        // Hand-written files (e.g. in ~/.config/touchy) may omit either key.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            bindings = try c.decodeIfPresent([String: GestureAction].self, forKey: .bindings) ?? [:]
        }
    }

    @Published var enabled: Bool {
        didSet { snapshotAndSave() }
    }

    /// Keyed by `Gesture.id`.
    @Published private(set) var bindings: [String: GestureAction] {
        didSet { snapshotAndSave() }
    }

    private let lock = NSLock()
    private var snapshot: Persisted

    private let files = ConfigFiles.standard

    private init() {
        if let decoded = files.load(Persisted.self, from: ConfigFiles.bindings) {
            enabled = decoded.enabled
            bindings = decoded.bindings
            snapshot = decoded
        } else {
            enabled = true
            bindings = [:]
            snapshot = Persisted(enabled: true, bindings: [:])
        }
        // Hand-edited files can contain typos like "swipe-3-upp": kept (and saved
        // back) untouched, but they can never fire, so say so.
        let unknown = bindings.keys.filter { id in !Gesture.all.contains { $0.id == id } }.sorted()
        if !unknown.isEmpty {
            NSLog("Touchy: bindings.json has unknown gesture id(s) that will never fire: \(unknown.joined(separator: ", "))")
        }
        if ProcessInfo.processInfo.environment["TOUCHY_DEBUG"] != nil {
            let summary = bindings.keys.sorted().map { key -> String in
                switch bindings[key]! {
                case .key: return "\(key)=key"
                case .click: return "\(key)=click"
                }
            }.joined(separator: " ")
            FileHandle.standardError.write(
                Data("[touchy] loaded \(bindings.count) binding(s) from \(files.url(for: ConfigFiles.bindings).path): \(summary)\n".utf8))
        }
    }

    func action(for gesture: Gesture) -> GestureAction? {
        bindings[gesture.id]
    }

    func setAction(_ action: GestureAction?, for gesture: Gesture) {
        if let action {
            bindings[gesture.id] = action
        } else {
            bindings.removeValue(forKey: gesture.id)
        }
    }

    /// Lock-protected lookup safe to call from the multitouch callback thread.
    /// Returns nil when globally disabled.
    func activeAction(forGestureID id: String) -> GestureAction? {
        lock.lock(); defer { lock.unlock() }
        guard snapshot.enabled else { return nil }
        return snapshot.bindings[id]
    }

    private func snapshotAndSave() {
        let current = Persisted(enabled: enabled, bindings: bindings)
        lock.lock()
        snapshot = current
        lock.unlock()
        files.save(current, to: ConfigFiles.bindings)
    }
}
