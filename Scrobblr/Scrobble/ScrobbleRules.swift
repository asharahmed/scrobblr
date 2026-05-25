import Foundation

/// Last.fm scrobbling rules + user overrides. https://www.last.fm/api/scrobbling
///
///   * Track must be longer than 30 seconds (Last.fm-mandated, not user-tunable).
///   * Submit when played time ≥ user threshold seconds OR ≥ user threshold
///     percent of duration, whichever first. Defaults: 240 s / 50%.
///   * Plays under `skipDebounce` are debounced as skips (5 s).
///
/// Pure functions. settings can be injected for tests via the explicit
/// overload. The `Duration`-typed entry point reads the live user settings
/// on the main actor.
enum ScrobbleRules {
    static let minTrackLength: Double = 30
    static let skipDebounce: Double = 5

    /// Reads thresholds from the user's saved settings.
    @MainActor
    static func qualifies(played: Duration, duration: Double?) -> Bool {
        let s = UserScrobbleSettings.shared
        return qualifies(playedSeconds: played.seconds,
                         duration: duration,
                         thresholdSeconds: s.thresholdSeconds,
                         thresholdPercent: s.thresholdPercent)
    }

    /// Test-friendly: explicit thresholds, no MainActor dependency.
    static func qualifies(playedSeconds played: Double,
                          duration: Double?,
                          thresholdSeconds: Double = 240,
                          thresholdPercent: Double = 0.5) -> Bool {
        guard let d = duration, d >= minTrackLength else { return false }
        if played < skipDebounce { return false }
        let needed = min(thresholdSeconds, d * thresholdPercent)
        return played >= needed
    }
}

private extension Duration {
    var seconds: Double {
        let comps = components
        return Double(comps.seconds) + Double(comps.attoseconds) / 1e18
    }
}
