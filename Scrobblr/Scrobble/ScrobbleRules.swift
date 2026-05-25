import Foundation

/// Last.fm scrobbling rules — https://www.last.fm/api/scrobbling
///
///   * Track must be longer than 30 seconds.
///   * Submit when played time ≥ 240 s OR ≥ 50% of duration, whichever first.
///   * Plays under 5 s are debounced as user skips.
///
/// Two overloads: one for `Duration` (preferred — fed by ContinuousClock,
/// immune to wall-clock skew), one for raw seconds (test convenience).
enum ScrobbleRules {
    static let minTrackLength: Double = 30
    static let absoluteThreshold: Double = 240
    static let skipDebounce: Double = 5

    static func qualifies(played: Duration, duration: Double?) -> Bool {
        qualifies(playedSeconds: played.seconds, duration: duration)
    }

    static func qualifies(playedSeconds played: Double, duration: Double?) -> Bool {
        guard let d = duration, d >= minTrackLength else { return false }
        if played < skipDebounce { return false }
        return played >= min(absoluteThreshold, d / 2)
    }
}

private extension Duration {
    /// Convert a Swift `Duration` to seconds as a Double.
    var seconds: Double {
        let comps = components
        return Double(comps.seconds) + Double(comps.attoseconds) / 1e18
    }
}
