import Foundation
import Combine

/// Wires the multitouch recognizer to binding lookup and key emission, and
/// publishes the most recent gesture for the UI's live indicator.
final class GestureEngine: ObservableObject {
    static let shared = GestureEngine()

    /// Most recently recognized gesture and whether it had a binding (for UI feedback).
    @Published var lastGesture: Gesture?
    @Published var lastGestureFired = false
    @Published var lastGestureAt: Date?

    private let reader = MultitouchReader.shared
    private let store = BindingStore.shared

    private init() {
        reader.recognizer.onGesture = { [weak self] gesture in
            self?.handle(gesture)
        }
    }

    func start() {
        reader.start()
    }

    /// Runs on the multitouch callback thread.
    private func handle(_ gesture: Gesture) {
        let combo = store.activeCombo(forGestureID: gesture.id)
        if ProcessInfo.processInfo.environment["TOUCHY_DEBUG"] != nil {
            FileHandle.standardError.write(
                Data("[touchy] recognized \(gesture.displayName) -> \(combo?.display ?? "(unbound)")\n".utf8))
        }
        if let combo {
            KeyEmitter.post(combo)
        }
        DispatchQueue.main.async {
            self.lastGesture = gesture
            self.lastGestureFired = (combo != nil)
            self.lastGestureAt = Date()
        }
    }
}
