import Foundation

/// A scrobble queued for submission to Last.fm. Timestamp is the moment the
/// track started, in Unix seconds UTC. Last.fm's protocol requires that.
struct ScrobbleRecord: Codable, Identifiable, Sendable {
    var id: UUID
    var artist: String
    var track: String
    var album: String?
    var albumArtist: String?
    var trackNumber: Int?
    var durationSeconds: Int?
    var timestamp: Int        // unix seconds UTC, track start
    var attempts: Int
    var lastAttempt: Date?

    init(track t: Track, startedAt: Date, id: UUID = UUID()) {
        self.id = id
        self.artist = t.artist
        self.track = t.title
        self.album = t.album
        self.albumArtist = t.albumArtist
        self.trackNumber = t.trackNumber
        self.durationSeconds = t.durationSeconds.map { Int($0) }
        self.timestamp = Int(startedAt.timeIntervalSince1970)
        self.attempts = 0
        self.lastAttempt = nil
    }
}
