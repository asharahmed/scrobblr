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

    // MARK: - Visual placeholder

    /// Deterministic hash of `identity` mapped into 0..<1, used to pick a
    /// placeholder hue. Same track always gets the same color across launches.
    /// The view layer turns this into a Color via Color(hue:saturation:brightness:).
    var identityHashHue: Double {
        // Hasher randomises seed per process; use a stable djb2 hash instead.
        var h: UInt64 = 5381
        for byte in identity.utf8 {
            h = ((h << 5) &+ h) &+ UInt64(byte)
        }
        return Double(h % 1000) / 1000.0
    }

    /// Single character used in the placeholder centre when there's no
    /// fetched album art. Prefers the first letter of the title; falls
    /// back to a music note glyph for emoji or non-letter titles.
    var placeholderInitial: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "♪" }
        if first.isLetter || first.isNumber {
            return String(first).uppercased()
        }
        return "♪"
    }
}
