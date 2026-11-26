import Foundation

/// Recognises a repeat of the same track when Music never reports a stop.
///
/// Repeat-one, repeat-all with a single song, and the same song queued twice
/// all restart the track without changing its identity. The notification
/// stream cannot tell those apart from normal progress, but the 1 Hz
/// playhead poll can: the position wraps from the end of the track back to
/// the start. Keeping the decision here makes it testable without timers or
/// Music itself.
enum PlaybackRestartDetector {
    /// Polls run at 1 Hz, so a wrap is normally observed under two seconds
    /// into the new play. The wider window tolerates a late timer.
    static let startWindow: Double = 10

    /// True when `new` looks like the beginning of a fresh play of a track
    /// that `previous` had already played past its halfway point.
    static func isRestart(
        previous: Double?,
        new: Double,
        duration: Double?,
        state: PlayerState
    ) -> Bool {
        guard state == .playing,
              let previous,
              let duration,
              duration >= ScrobbleRules.minTrackLength,
              previous > duration * 0.5,
              new < startWindow
        else { return false }
        return true
    }
}
