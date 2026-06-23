import Foundation
import AppKit
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
    private var sleepWakeObservers: [NSObjectProtocol] = []
    private var retryCount = 0
    private let maxRetries = 5
    private let retryDelaySeconds = 0.5

    private init() {}

    func start() {
        installSleepWakeObserversIfNeeded()
        guard !isRunning else { return }

        // Always re-enumerate so a restart picks up fresh device handles.
        devices = []
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

    /// MultitouchSupport stops delivering frames after the system or display
    /// sleeps and never resumes on its own, so re-initialize the devices on wake.
    func restart() {
        dbg("restart: re-initialising multitouch (wake)")
        stop()
        start()
    }

    /// Restart with verification and retry on wake, handling HID stack initialization race.
    /// If devices don't report running after start(), schedule a retry with bounded attempts.
    private func restartWithRetry() {
        dbg("restartWithRetry: stopping and restarting multitouch")
        stop()
        start()

        // Verify that at least one device is actually running; if not, retry.
        if !devices.isEmpty && !devices.contains(where: { MTDeviceIsRunning($0) }) {
            retryCount += 1
            if retryCount <= maxRetries {
                dbg("restartWithRetry: attempt \(retryCount)/\(maxRetries) - no device running, retrying in \(retryDelaySeconds)s")
                DispatchQueue.main.asyncAfter(deadline: .now() + retryDelaySeconds) { [weak self] in
                    self?.restartWithRetry()
                }
            } else {
                dbg("restartWithRetry: gave up after \(maxRetries) attempts - multitouch may not recover")
                retryCount = 0
            }
        } else {
            // At least one device is running or no devices found at all; success or handled by start().
            retryCount = 0
            if !devices.isEmpty {
                dbg("restartWithRetry: devices confirmed running")
            }
        }
    }

    /// Install observers for both sleep and wake events.
    /// On sleep, stop cleanly to release devices while handles are valid.
    /// On wake, restart with verification and retry to handle HID stack timing races.
    private func installSleepWakeObserversIfNeeded() {
        guard sleepWakeObservers.isEmpty else { return }
        let nc = NSWorkspace.shared.notificationCenter

        // Stop on sleep to release devices cleanly.
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            let token = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.stop()
            }
            sleepWakeObservers.append(token)
        }

        // Restart with verification on wake.
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            let token = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.restartWithRetry()
            }
            sleepWakeObservers.append(token)
        }
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
