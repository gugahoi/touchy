import Foundation
import Combine

/// Holds gesture→key-combo bindings and the global enable flag, persisted as JSON
/// in Application Support. Observable so the UI updates live; thread-safe reads via
/// a lock so the multitouch callback thread can look up bindings without hopping.
final class BindingStore: ObservableObject {
    static let shared = BindingStore()

    struct Persisted: Codable {
        var enabled: Bool
        var bindings: [String: KeyCombo]
    }

    @Published var enabled: Bool {
        didSet { snapshotAndSave() }
    }

    /// Keyed by `Gesture.id`.
    @Published private(set) var bindings: [String: KeyCombo] {
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
    }

    func combo(for gesture: Gesture) -> KeyCombo? {
        bindings[gesture.id]
    }

    func setCombo(_ combo: KeyCombo?, for gesture: Gesture) {
        if let combo {
            bindings[gesture.id] = combo
        } else {
            bindings.removeValue(forKey: gesture.id)
        }
    }

    /// Lock-protected lookup safe to call from the multitouch callback thread.
    /// Returns nil when globally disabled.
    func activeCombo(forGestureID id: String) -> KeyCombo? {
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
