import Foundation

struct Track: Codable, Hashable, Sendable {
    var title: String
    var artist: String
    var album: String?
    var albumArtist: String?
    var trackNumber: Int?
    var durationSeconds: Double?
    var persistentID: String?
    var storeAdamID: String?
    var origin: Origin

    enum Origin: String, Codable, Sendable {
        case localFile
        case appleMusicCatalog
        case stream
        case unknown
    }

    /// Stable identity used to detect same-track-replayed and dedupe scrobbles.
    /// `persistentID` (library) and `storeAdamID` (Apple Music catalog) are
    /// reliable when present. When both are missing — e.g. notification-only
    /// path with a track absent from your library — we fall back to a tuple
    /// keyed on lowercased metadata. Note: callers should pair `identity`
    /// with the play's `startedAt` to disambiguate distinct plays of the
    /// same track (replays). See ScrobbleEngine.Candidate.
    var identity: String {
        if let pid = persistentID, !pid.isEmpty { return "pid:\(pid)" }
        if let adam = storeAdamID, !adam.isEmpty { return "adam:\(adam)" }
        let dur = durationSeconds.map { Int($0) } ?? 0
        return "tuple:\(origin.rawValue):\(artist.lowercased())|\(album?.lowercased() ?? "")|\(title.lowercased())|\(dur)"
    }

    /// Last.fm rule: tracks shorter than 30s are never scrobbled. We also
    /// refuse to scrobble streams (Apple Music Radio, internet radio) and
    /// anything missing the mandatory artist+title pair.
    var isScrobbleEligible: Bool {
        guard !artist.isEmpty, !title.isEmpty else { return false }
        if let d = durationSeconds, d < 30 { return false }
        if origin == .stream { return false }
        return true
    }
}
