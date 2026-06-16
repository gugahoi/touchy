import Foundation
import CMultitouch

private let recognizerDebug = ProcessInfo.processInfo.environment["TOUCHY_DEBUG"] != nil
private func rdbg(_ s: String) {
    if recognizerDebug { FileHandle.standardError.write(Data("[touchy] \(s)\n".utf8)) }
}

/// Classifies raw multitouch frames into discrete gestures.
///
/// State machine over a single touch sequence (fingers down → fingers up):
/// - A sequence begins when ≥3 fingers are present.
/// - Movement is accumulated frame-to-frame as a net centroid displacement, but
///   only across frames where the finger count is unchanged and the per-frame
///   step is small. This skips the centroid jump that happens when a finger lands
///   or lifts (which would otherwise inflate movement and break tap/swipe alike),
///   while real gesture motion always accumulates regardless of brief count
///   flicker (e.g. a stray 4th finger during a 3-finger swipe).
/// - Past `swipeThreshold` of net travel → swipe in the dominant direction (once).
/// - On lift, if nothing was recognized and the sequence was short and nearly
///   stationary → tap, using the peak finger count seen.
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
    /// Quiet period (seconds) after an emit before another gesture can fire.
    /// Short enough that deliberate repeated taps register; long enough to debounce
    /// the finger-lift jitter of a single physical gesture.
    var cooldown: Double = 0.25

    var onGesture: ((Gesture) -> Void)?

    private struct Point { var x: Double; var y: Double }

    private var active = false
    private var recognized = false
    private var startTime: Double = 0
    private var peakFingers = 0
    private var lastEmitTime: Double = -1

    private var lastCount = 0
    private var lastCentroid = Point(x: 0, y: 0)
    private var netDX = 0.0
    private var netDY = 0.0

    /// Called once per multitouch frame.
    func ingest(fingers: UnsafePointer<Finger>?, count: Int, timestamp: Double) {
        if count == 0 {
            if active { endSequence(at: timestamp) }
            return
        }

        let centroid = computeCentroid(fingers: fingers, count: count)

        if !active {
            // Ignore 1–2 finger touches entirely (OS-owned).
            guard count >= 3 else { return }
            beginSequence(centroid: centroid, count: count, timestamp: timestamp)
            return
        }

        peakFingers = max(peakFingers, count)

        // Accumulate motion only across continuous frames (same finger count, small
        // step). Finger landings/liftings change the count and/or jump the centroid,
        // and are deliberately excluded.
        if count == lastCount {
            let dx = centroid.x - lastCentroid.x
            let dy = centroid.y - lastCentroid.y
            if (dx * dx + dy * dy).squareRoot() <= jumpCap {
                netDX += dx
                netDY += dy
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
        rdbg(String(format: "seq end: peakFingers=%d dur=%.2f netDist=%.3f recognized=%@",
                    peakFingers, duration, netDistance, recognized ? "yes" : "no"))

        guard !recognized, peakFingers >= 3, !inCooldown(timestamp) else { return }

        if duration <= tapMaxDuration && netDistance <= tapMaxMovement {
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

    private func computeCentroid(fingers: UnsafePointer<Finger>?, count: Int) -> Point {
        guard let fingers, count > 0 else { return Point(x: 0, y: 0) }
        var sx = 0.0, sy = 0.0
        for i in 0..<count {
            let p = fingers[i].normalizedVector.position
            sx += Double(p.x)
            sy += Double(p.y)
        }
        return Point(x: sx / Double(count), y: sy / Double(count))
    }
}
