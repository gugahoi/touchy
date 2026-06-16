import AppKit
import Combine
import Carbon.HIToolbox

/// Captures the next key chord the user presses, for assigning to a gesture.
/// Installs a local key-down monitor while recording so the keystroke is consumed
/// by the recorder instead of reaching the focused control.
final class KeyRecorder: ObservableObject {
    /// The `Gesture.id` currently being recorded, or nil when idle.
    @Published var recordingID: String?

    private var monitor: Any?
    private var onCapture: ((KeyCombo) -> Void)?

    private var globalMonitor: Any?

    func startRecording(for gestureID: String, onCapture: @escaping (KeyCombo) -> Void) {
        stop()
        recordingID = gestureID
        self.onCapture = onCapture

        // The MenuBarExtra popover doesn't reliably take keyboard focus for an
        // accessory app, so explicitly activate to make the local monitor fire.
        NSApp.activate(ignoringOtherApps: true)

        // Local monitor consumes the keystroke (returns nil) when we're focused.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.capture(event) ? nil : event
        }

        // Global fallback: if the popover still isn't key, this catches the key
        // (it can't consume the event, but capture is what matters here).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.capture(event)
        }
    }

    /// Returns true if the event was handled (captured or cancelled).
    private func capture(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }

        // Escape cancels without binding.
        if event.keyCode == kVK_Escape,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            stop()
            return true
        }

        // Ignore lone modifier presses; wait for a real key.
        onCapture?(KeyCombo.from(event: event))
        stop()
        return true
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        recordingID = nil
        onCapture = nil
    }

    var isRecording: Bool { recordingID != nil }
}
