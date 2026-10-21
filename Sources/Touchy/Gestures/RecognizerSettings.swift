import Foundation

/// User-tunable gesture recognition thresholds, edited in the Settings pane.
/// Distances are fractions of the trackpad (normalized 0–1 coordinates);
/// durations are seconds.
struct RecognizerSettings: Equatable {
    /// Net centroid travel needed to call a swipe.
    var swipeThreshold = 0.12
    /// For a swipe, each of at least 3 fingers must itself travel this fraction of
    /// `swipeThreshold` in the swipe direction, so a resting thumb/palm plus two
    /// scrolling fingers doesn't count. 0 disables the check.
    var fingerTravelRatio = 0.5
    /// Max net travel still considered a tap (forgiving of slight drift).
    var tapMaxMovement = 0.10
    /// Max duration still considered a tap.
    var tapMaxDuration = 0.4
    /// Quiet period after an emit before another gesture can fire. Short enough
    /// that deliberate repeated taps register; long enough to debounce the
    /// finger-lift jitter of a single physical gesture.
    var cooldown = 0.25

    // Supported ranges — shared by the Settings sliders and decode-time clamping.
    static let swipeThresholdRange: ClosedRange<Double> = 0.04...0.30
    static let fingerTravelRatioRange: ClosedRange<Double> = 0...1
    static let tapMaxMovementRange: ClosedRange<Double> = 0.02...0.20
    static let tapMaxDurationRange: ClosedRange<Double> = 0.1...1.0
    static let cooldownRange: ClosedRange<Double> = 0...1.0

    /// Every field forced into its supported range (guards hand-edited JSON).
    func clamped() -> RecognizerSettings {
        func clamp(_ v: Double, _ r: ClosedRange<Double>) -> Double {
            v.isFinite ? min(max(v, r.lowerBound), r.upperBound) : r.lowerBound
        }
        var s = self
        s.swipeThreshold = clamp(swipeThreshold, Self.swipeThresholdRange)
        s.fingerTravelRatio = clamp(fingerTravelRatio, Self.fingerTravelRatioRange)
        s.tapMaxMovement = clamp(tapMaxMovement, Self.tapMaxMovementRange)
        s.tapMaxDuration = clamp(tapMaxDuration, Self.tapMaxDurationRange)
        s.cooldown = clamp(cooldown, Self.cooldownRange)
        return s
    }
}

extension RecognizerSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case swipeThreshold, fingerTravelRatio, tapMaxMovement, tapMaxDuration, cooldown
    }

    // Defensive decode: missing fields (older/partial files) fall back to defaults
    // and out-of-range values are clamped, so a bad file never throws.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RecognizerSettings()
        swipeThreshold = (try? c.decodeIfPresent(Double.self, forKey: .swipeThreshold)) ?? d.swipeThreshold
        fingerTravelRatio = (try? c.decodeIfPresent(Double.self, forKey: .fingerTravelRatio)) ?? d.fingerTravelRatio
        tapMaxMovement = (try? c.decodeIfPresent(Double.self, forKey: .tapMaxMovement)) ?? d.tapMaxMovement
        tapMaxDuration = (try? c.decodeIfPresent(Double.self, forKey: .tapMaxDuration)) ?? d.tapMaxDuration
        cooldown = (try? c.decodeIfPresent(Double.self, forKey: .cooldown)) ?? d.cooldown
        self = clamped()
    }
}
