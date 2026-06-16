import Foundation
import Combine

/// Holds gesture→action bindings and the global enable flag, persisted as JSON in
/// Application Support. Observable so the UI updates live; thread-safe reads via a
/// lock so the multitouch callback thread can look up bindings without hopping.
///
/// Legacy `bindings.json` files stored bare `KeyCombo` dicts as values; those
/// decode transparently as `.key` actions (see `GestureAction.init(from:)`).
final class BindingStore: ObservableObject {
    static let shared = BindingStore()

    struct Persisted: Codable {
        var enabled: Bool
        var bindings: [String: GestureAction]
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

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Touchy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("bindings.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Persisted.self, from: data) {
            enabled = decoded.enabled
            bindings = decoded.bindings
            snapshot = decoded
        } else {
            enabled = true
            bindings = [:]
            snapshot = Persisted(enabled: true, bindings: [:])
        }
        if ProcessInfo.processInfo.environment["TOUCHY_DEBUG"] != nil {
            let summary = bindings.keys.sorted().map { key -> String in
                switch bindings[key]! {
                case .key: return "\(key)=key"
                case .click: return "\(key)=click"
                }
            }.joined(separator: " ")
            FileHandle.standardError.write(
                Data("[touchy] loaded \(bindings.count) binding(s): \(summary)\n".utf8))
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
        if let data = try? JSONEncoder().encode(current) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
