import Foundation
import CMultitouch

private let debugEnabled = ProcessInfo.processInfo.environment["TOUCHY_DEBUG"] != nil
private func dbg(_ s: String) {
    if debugEnabled { FileHandle.standardError.write(Data("[touchy] \(s)\n".utf8)) }
}

/// Owns the MultitouchSupport devices and feeds frames into a `GestureRecognizer`.
///
/// The `@convention(c)` frame callback cannot capture Swift context, so it routes
/// every frame through the `shared` singleton. Reading touch frames needs no special
/// permission (verified empirically); only key *output* requires Accessibility.
final class MultitouchReader {
    static let shared = MultitouchReader()

    let recognizer = GestureRecognizer()
    private var devices: [MTDeviceRef] = []
    private(set) var isRunning = false

    private init() {}

    func start() {
        guard !isRunning else { return }

        // Prefer the full device list (external trackpads / multiple devices);
        // fall back to the default device.
        if let list = MTDeviceCreateList()?.takeRetainedValue() as? [MTDeviceRef] {
            devices = list
        }
        if devices.isEmpty, let def = MTDeviceCreateDefault() {
            devices = [def]
        }
        guard !devices.isEmpty else {
            NSLog("Touchy: no multitouch device found")
            dbg("start: NO DEVICES FOUND")
            return
        }

        for device in devices {
            MTRegisterContactFrameCallback(device, mtFrameCallback)
            MTDeviceStart(device, 0)
        }
        isRunning = true
        dbg("start: \(devices.count) device(s) started")
    }

    func stop() {
        guard isRunning else { return }
        for device in devices {
            MTUnregisterContactFrameCallback(device, mtFrameCallback)
            MTDeviceStop(device)
        }
        isRunning = false
    }

    private var frameCount = 0
    fileprivate func handleFrame(fingers: UnsafeMutablePointer<Finger>?, count: Int, timestamp: Double) {
        if debugEnabled {
            frameCount += 1
            if count >= 3 && frameCount % 15 == 0 { dbg("frame: \(count) fingers") }
        }
        recognizer.ingest(fingers: fingers, count: count, timestamp: timestamp)
    }
}

/// Global C callback — fires on the framework's own thread, forwards to the singleton.
private let mtFrameCallback: MTContactCallbackFunction = { _, fingers, numFingers, timestamp, _ in
    MultitouchReader.shared.handleFrame(
        fingers: fingers,
        count: Int(numFingers),
        timestamp: timestamp
    )
    return 0
}
