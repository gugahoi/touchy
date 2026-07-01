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
    private var watchdog: Timer?
    private let watchdogIntervalSeconds = 3.0

    private init() {}

    func start() {
        installSleepWakeObserversIfNeeded()
        installWatchdogIfNeeded()
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

    /// Self-healing safety net. Recovery can't hinge on catching a single wake
    /// notification: many wake paths (DarkWake, Maintenance Sleep) post no
    /// `NSWorkspace` notification at all, and the HID stack can take longer than
    /// any fixed post-wake retry window to come back. So instead of a one-shot
    /// bounded retry, poll liveness forever and re-arm whenever we believe we
    /// should be running but no device is.
    ///
    /// `MTDeviceIsRunning` is the right signal: it stays `true` on a healthy but
    /// idle device (an untouched pad delivers zero frames), so a frame-based
    /// check would false-positive; and it reads `false` while the device is
    /// down, so this catches the dead state without thrashing during normal idle.
    // ponytail: catches deaths where the device reports not-running. A device
    // that reports running while silently delivering no frames would slip past
    // this — never observed, add frame-liveness tracking if it ever happens.
    private func installWatchdogIfNeeded() {
        guard watchdog == nil else { return }
        watchdog = Timer.scheduledTimer(withTimeInterval: watchdogIntervalSeconds, repeats: true) { [weak self] _ in
            guard let self, self.isRunning, !self.devices.isEmpty,
                  !self.devices.contains(where: { MTDeviceIsRunning($0) }) else { return }
            dbg("watchdog: device stopped delivering, re-arming")
            self.restart()
        }
    }

    /// Install observers for both sleep and wake events.
    /// On sleep, stop cleanly to release devices while handles are valid.
    /// On wake, restart immediately; the watchdog re-arms anything this misses.
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

        // Restart on wake for immediate recovery; the watchdog is the backstop.
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            let token = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.restart()
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
