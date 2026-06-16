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

    /// Runs on the multitouch callback thread. Only `CGEvent` posting is safe here;
    /// `KeyCombo.display` (Text Input Source APIs) and `@Published` updates must run
    /// on the main thread, so everything else is dispatched.
    private func handle(_ gesture: Gesture) {
        let action = store.activeAction(forGestureID: gesture.id)
        if let action {
            KeyEmitter.perform(action)
        }
        DispatchQueue.main.async {
            if ProcessInfo.processInfo.environment["TOUCHY_DEBUG"] != nil {
                FileHandle.standardError.write(
                    Data("[touchy] recognized \(gesture.displayName) -> \(action?.display ?? "(unbound)")\n".utf8))
            }
            self.lastGesture = gesture
            self.lastGestureFired = (action != nil)
            self.lastGestureAt = Date()
        }
    }
}
