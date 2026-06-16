import Foundation
import CMultitouch

private let recognizerDebug = ProcessInfo.processInfo.environment["TOUCHY_DEBUG"] != nil
private func rdbg(_ s: String) {
    if recognizerDebug { FileHandle.standardError.write(Data("[touchy] \(s)\n".utf8)) }
}

/// Classifies raw multitouch frames into discrete gestures.
///
/// State machine over a single touch sequence (fingers down → fingers up):
/// - A sequence begins when ≥3 fingers are present and records a reference centroid.
/// - While fingers are down, if the centroid travels past `swipeThreshold`, it emits
///   a swipe in the dominant direction (once per sequence) and locks recognition.
/// - When all fingers lift: if nothing was recognized and the sequence was short and
///   nearly stationary, it emits a tap using the peak finger count seen.
/// A `cooldown` after any emit prevents a single physical gesture firing repeatedly.
final class GestureRecognizer {
    /// Normalized centroid travel (fraction of pad) needed to call a swipe.
    var swipeThreshold: Double = 0.12
    /// Max centroid travel still considered a tap (forgiving of slight drift).
    var tapMaxMovement: Double = 0.10
    /// Max duration (seconds) still considered a tap.
    var tapMaxDuration: Double = 0.4
    /// Quiet period (seconds) after an emit before another gesture can fire.
    /// Short enough that deliberate repeated taps register; long enough to debounce
    /// the finger-lift jitter of a single physical gesture.
    var cooldown: Double = 0.25

    var onGesture: ((Gesture) -> Void)?

    private struct Point { var x: Double; var y: Double }

    private var active = false
    private var recognized = false
    private var startCentroid = Point(x: 0, y: 0)
    private var startTime: Double = 0
    private var peakFingers = 0
    private var lastEmitTime: Double = -1
    private var maxDistance: Double = 0

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

        // A new finger landed: re-anchor measurement to this moment. Fingers land
        // staggered, and the centroid jumps each time one touches down — measuring
        // from a partial-contact start would inflate "movement" and wrongly reject
        // taps. Re-baselining means we only ever measure the full-hand phase.
        if count > peakFingers {
            peakFingers = count
            startCentroid = centroid
            startTime = timestamp
            maxDistance = 0
            return
        }

        // Only evaluate while the full finger set is down. While fingers lift one by
        // one (count < peak), the centroid shifts toward the remaining fingers; that
        // isn't real gesture movement, so ignore it.
        guard count == peakFingers else { return }
        guard !recognized, peakFingers >= 3, !inCooldown(timestamp) else { return }

        let dx = centroid.x - startCentroid.x
        let dy = centroid.y - startCentroid.y
        let distance = (dx * dx + dy * dy).squareRoot()
        maxDistance = max(maxDistance, distance)

        if distance >= swipeThreshold {
            let direction: SwipeDirection
            if abs(dx) >= abs(dy) {
                direction = dx > 0 ? .right : .left
            } else {
                direction = dy > 0 ? .up : .down
            }
            emit(.swipe(clampFingers(peakFingers), direction), at: timestamp)
            recognized = true
        }
    }

    private func beginSequence(centroid: Point, count: Int, timestamp: Double) {
        active = true
        recognized = false
        startCentroid = centroid
        startTime = timestamp
        peakFingers = count
        maxDistance = 0
        rdbg("seq begin: fingers=\(count)")
    }

    private func endSequence(at timestamp: Double) {
        defer {
            active = false
            recognized = false
            peakFingers = 0
        }
        let duration = timestamp - startTime
        rdbg(String(format: "seq end: peakFingers=%d dur=%.2f maxDist=%.3f recognized=%@",
                    peakFingers, duration, maxDistance, recognized ? "yes" : "no"))

        guard !recognized, peakFingers >= 3, !inCooldown(timestamp) else { return }

        if duration <= tapMaxDuration && maxDistance <= tapMaxMovement {
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
