import Foundation
import CMultitouch

private let recognizerDebug = ProcessInfo.processInfo.environment["TOUCHY_DEBUG"] != nil
private func rdbg(_ s: String) {
    if recognizerDebug { FileHandle.standardError.write(Data("[touchy] \(s)\n".utf8)) }
}

extension Finger {
    /// MultitouchSupport reports every contact it can sense, not just fingers on
    /// the glass: fingers hovering just above the pad (states 1–2) and fingers that
    /// just lifted, which linger for several frames (5–7). Only 3 (make touch) and
    /// 4 (touching) are real contacts. Counting the others turns an ordinary
    /// 2-finger scroll into a "3-finger" one (e.g. a lingering finger from the
    /// previous scroll flick, or a ring finger hovering over the pad).
    var isTouching: Bool { state == 3 || state == 4 }
}

/// Classifies raw multitouch frames into discrete gestures.
///
/// Only contacts that are actually touching the pad (`Finger.isTouching`) are
/// considered; hovering and lingering contacts are ignored entirely.
///
/// State machine over a single touch sequence (fingers down → fingers up):
/// - A sequence begins when ≥3 fingers are present.
/// - Movement is accumulated frame-to-frame as a net centroid displacement, but
///   only across frames where the finger count is unchanged and the per-frame
///   step is small. This skips the centroid jump that happens when a finger lands
///   or lifts (which would otherwise inflate movement and break tap/swipe alike),
///   while real gesture motion always accumulates regardless of brief count
///   flicker (e.g. a stray 4th finger during a 3-finger swipe).
/// - Only frames with ≥3 fingers count toward a swipe. A sequence stays open until
///   every finger lifts, so without this a brief 3rd contact followed by a plain
///   2-finger scroll would be reported as a 3-finger swipe.
/// - Past `swipeThreshold` of net travel → swipe in the dominant direction (once),
///   provided at least 3 individual fingers moved that way. A resting thumb or palm
///   plus two scrolling fingers moves the centroid too, but only 2 fingers travel.
/// - On lift, if nothing was recognized and the sequence was short and nearly
///   stationary (measured over all frames, including <3-finger ones) → tap, using
///   the peak finger count seen.
/// A `cooldown` after any emit prevents one physical gesture firing repeatedly.
final class GestureRecognizer {
    /// Net centroid travel (fraction of pad) needed to call a swipe.
    var swipeThreshold: Double = 0.12
    /// Max net travel still considered a tap (forgiving of slight drift).
    var tapMaxMovement: Double = 0.10
    /// Max duration (seconds) still considered a tap.
    var tapMaxDuration: Double = 0.4
    /// Per-frame centroid step above this is treated as a finger-change
    /// discontinuity and not accumulated as motion.
    var jumpCap: Double = 0.08
    /// For a swipe, each of at least 3 fingers must itself have travelled this
    /// fraction of `swipeThreshold` in the swipe direction.
    var fingerTravelRatio: Double = 0.5
    /// Quiet period (seconds) after an emit before another gesture can fire.
    /// Short enough that deliberate repeated taps register; long enough to debounce
    /// the finger-lift jitter of a single physical gesture.
    var cooldown: Double = 0.25

    var onGesture: ((Gesture) -> Void)?

    /// Clears all cross-sequence state. Must be called when the multitouch device
    /// session restarts (sleep/wake): the framework's timestamp is session-relative
    /// and resets low on restart, so a stale `lastEmitTime` from the previous
    /// session would make `inCooldown` return true forever and wedge recognition.
    func reset() {
        active = false
        recognized = false
        peakFingers = 0
        netDX = 0
        netDY = 0
        tapDX = 0
        tapDY = 0
        origins.removeAll(keepingCapacity: true)
        rejectionLogged = false
        lastCount = 0
        lastEmitTime = -1
    }

    private struct Point { var x: Double; var y: Double }

    private var active = false
    private var recognized = false
    private var startTime: Double = 0
    private var peakFingers = 0
    private var lastEmitTime: Double = -1

    private var lastCount = 0
    private var lastCentroid = Point(x: 0, y: 0)
    /// Net motion over ≥3-finger frames only — drives swipe detection.
    private var netDX = 0.0
    private var netDY = 0.0
    /// Net motion over all frames — a tap must be stationary throughout.
    private var tapDX = 0.0
    private var tapDY = 0.0

    /// Where each finger (by `identifier`) was first seen touching in this sequence.
    private struct Origin { var id: Int32; var point: Point }
    private var origins: [Origin] = []
    private var rejectionLogged = false

    /// Called once per multitouch frame. `count` is the raw contact count reported
    /// by the framework; non-touching contacts are filtered out here.
    func ingest(fingers: UnsafePointer<Finger>?, count rawCount: Int, timestamp: Double) {
        let (count, centroid) = touchingCentroid(fingers: fingers, count: rawCount)

        if count == 0 {
            if active { endSequence(at: timestamp) }
            return
        }

        if !active {
            // Ignore 1–2 finger touches entirely (OS-owned).
            guard count >= 3 else { return }
            beginSequence(centroid: centroid, count: count, timestamp: timestamp)
            recordOrigins(fingers: fingers, count: rawCount)
            return
        }

        peakFingers = max(peakFingers, count)
        recordOrigins(fingers: fingers, count: rawCount)

        // Accumulate motion only across continuous frames (same finger count, small
        // step). Finger landings/liftings change the count and/or jump the centroid,
        // and are deliberately excluded.
        if count == lastCount {
            let dx = centroid.x - lastCentroid.x
            let dy = centroid.y - lastCentroid.y
            if (dx * dx + dy * dy).squareRoot() <= jumpCap {
                tapDX += dx
                tapDY += dy
                if count >= 3 {
                    netDX += dx
                    netDY += dy
                }
            }
        }
        lastCount = count
        lastCentroid = centroid

        guard !recognized, peakFingers >= 3, !inCooldown(timestamp) else { return }

        let distance = (netDX * netDX + netDY * netDY).squareRoot()
        if distance >= swipeThreshold {
            let direction: SwipeDirection
            if abs(netDX) >= abs(netDY) {
                direction = netDX > 0 ? .right : .left
            } else {
                direction = netDY > 0 ? .up : .down
            }
            let movers = fingersTravelled(direction, fingers: fingers, count: rawCount)
            guard movers >= 3 else {
                if !rejectionLogged {
                    rejectionLogged = true
                    rdbg(String(format: "swipe %@ rejected: only %d finger(s) moved (net=%.3f, peak=%d)",
                                direction.rawValue, movers, distance, peakFingers))
                }
                return
            }
            emit(.swipe(clampFingers(peakFingers), direction), at: timestamp)
            recognized = true
        }
    }

    private func beginSequence(centroid: Point, count: Int, timestamp: Double) {
        active = true
        recognized = false
        startTime = timestamp
        peakFingers = count
        lastCount = count
        lastCentroid = centroid
        netDX = 0
        netDY = 0
        tapDX = 0
        tapDY = 0
        origins.removeAll(keepingCapacity: true)
        rejectionLogged = false
        rdbg("seq begin: fingers=\(count)")
    }

    private func endSequence(at timestamp: Double) {
        defer {
            active = false
            recognized = false
            peakFingers = 0
        }
        let duration = timestamp - startTime
        let netDistance = (netDX * netDX + netDY * netDY).squareRoot()
        let tapDistance = (tapDX * tapDX + tapDY * tapDY).squareRoot()
        rdbg(String(format: "seq end: peakFingers=%d dur=%.2f netDist=%.3f tapDist=%.3f recognized=%@",
                    peakFingers, duration, netDistance, tapDistance, recognized ? "yes" : "no"))

        guard !recognized, peakFingers >= 3, !inCooldown(timestamp) else { return }

        if duration <= tapMaxDuration && tapDistance <= tapMaxMovement {
            emit(.tap(clampFingers(peakFingers)), at: timestamp)
        }
    }

    private func emit(_ gesture: Gesture, at timestamp: Double) {
        lastEmitTime = timestamp
        onGesture?(gesture)
    }

    private func inCooldown(_ timestamp: Double) -> Bool {
        lastEmitTime >= 0 && (timestamp - lastEmitTime) < cooldown
    }

    private func clampFingers(_ n: Int) -> Int { min(max(n, 3), 5) }

    /// Number of touching contacts and their centroid.
    private func touchingCentroid(fingers: UnsafePointer<Finger>?, count: Int) -> (Int, Point) {
        guard let fingers, count > 0 else { return (0, Point(x: 0, y: 0)) }
        var n = 0
        var sx = 0.0, sy = 0.0
        for i in 0..<count where fingers[i].isTouching {
            let p = fingers[i].normalizedVector.position
            sx += Double(p.x)
            sy += Double(p.y)
            n += 1
        }
        guard n > 0 else { return (0, Point(x: 0, y: 0)) }
        return (n, Point(x: sx / Double(n), y: sy / Double(n)))
    }

    private func recordOrigins(fingers: UnsafePointer<Finger>?, count: Int) {
        guard let fingers else { return }
        for i in 0..<count where fingers[i].isTouching {
            let f = fingers[i]
            if !origins.contains(where: { $0.id == f.identifier }) {
                let p = f.normalizedVector.position
                origins.append(Origin(id: f.identifier, point: Point(x: Double(p.x), y: Double(p.y))))
            }
        }
    }

    /// How many currently-touching fingers have individually travelled far enough
    /// in `direction` since they were first seen in this sequence.
    private func fingersTravelled(_ direction: SwipeDirection,
                                  fingers: UnsafePointer<Finger>?, count: Int) -> Int {
        guard let fingers else { return 0 }
        let minTravel = swipeThreshold * fingerTravelRatio
        var movers = 0
        for i in 0..<count where fingers[i].isTouching {
            let f = fingers[i]
            guard let origin = origins.first(where: { $0.id == f.identifier })?.point else { continue }
            let p = f.normalizedVector.position
            let dx = Double(p.x) - origin.x
            let dy = Double(p.y) - origin.y
            let travel: Double
            switch direction {
            case .up: travel = dy
            case .down: travel = -dy
            case .right: travel = dx
            case .left: travel = -dx
            }
            if travel >= minTravel { movers += 1 }
        }
        return movers
    }
}
