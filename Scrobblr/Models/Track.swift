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
        case podcast
        case audiobook
        case musicVideo
        case unknown
    }

    /// Stable identity used to detect same-track-replayed and dedupe scrobbles.
    /// `persistentID` (library) and `storeAdamID` (Apple Music catalog) are
    /// reliable when present. When both are missing. e.g. notification-only
    /// path with a track absent from your library. we fall back to a tuple
    /// keyed on lowercased metadata. Note: callers should pair `identity`
    /// with the play's `startedAt` to disambiguate distinct plays of the
    /// same track (replays). See ScrobbleEngine.Candidate.
    var identity: String {
        if let pid = persistentID, !pid.isEmpty { return "pid:\(pid)" }
        if let adam = storeAdamID, !adam.isEmpty { return "adam:\(adam)" }
        let dur = durationSeconds.map { Int($0) } ?? 0
        return "tuple:\(origin.rawValue):\(artist.lowercased())|\(album?.lowercased() ?? "")|\(title.lowercased())|\(dur)"
    }

    /// Last.fm rule: tracks shorter than 30 s are never scrobbled. Streams
    /// (Apple Music Radio, internet radio) are never scrobbled. Podcasts,
    /// audiobooks, and music videos are user-toggleable via
    /// UserScrobbleSettings.
    ///
    /// Pure rule evaluation. no UserDefaults lookup. The engine calls
    /// `isScrobbleEligible(settings:ignoreRules:)` to apply user overrides.
    var isScrobbleEligible: Bool {
        guard !artist.isEmpty, !title.isEmpty else { return false }
        if let d = durationSeconds, d < 30 { return false }
        if origin == .stream { return false }
        return true
    }

    /// Eligibility including user settings + ignore rules. Used by the
    /// engine at enqueue + Now Playing time. Sendable parameters so this
    /// can be called from any actor.
    @MainActor
    func isScrobbleEligibleWithUserOverrides() -> Bool {
        guard isScrobbleEligible else { return false }
        let s = UserScrobbleSettings.shared
        if s.skipPodcasts, origin == .podcast { return false }
        if s.skipAudiobooks, origin == .audiobook { return false }
        if s.skipMusicVideos, origin == .musicVideo { return false }
        if IgnoreRules.shared.shouldIgnoreTrack(artist: artist, title: title) { return false }
        return true
    }
}
