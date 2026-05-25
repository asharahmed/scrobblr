import Foundation

enum PlayerState: String, Sendable {
    case stopped
    case paused
    case playing
}

/// One coherent snapshot the rest of the app reasons about.
struct PlaybackSnapshot: Sendable {
    var state: PlayerState
    var track: Track?
    var position: Double?        // seconds into the current track
    var startedAt: Date?         // when the current play of `track` began
}
