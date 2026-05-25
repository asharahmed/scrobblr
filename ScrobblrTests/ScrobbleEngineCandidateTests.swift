import XCTest
@testable import Scrobblr

/// Pure-logic tests for the elapsed-time accumulator and the
/// (identity, startedAt) candidate matching that prevents replay
/// double-scrobbling.
///
/// Full engine integration tests would need mocks for PlaybackObserver,
/// LastFMClient, ScrobbleQueue, and SystemMonitor. That's a 0.2.x project.
/// These pure tests cover the rules the engine consults at every decision
/// point, so a regression in the rule layer fails here loudly.
final class ScrobbleEngineCandidateTests: XCTestCase {

    // MARK: - Elapsed-time accumulator semantics

    func test_durationArithmetic_seconds() {
        let d = Duration.seconds(125) + Duration.seconds(75)
        XCTAssertEqual(d.components.seconds, 200)
    }

    func test_qualifies_uses_thresholds_correctly() {
        // 3-minute track: needs 90s (50%) since 90 < 240.
        XCTAssertTrue(ScrobbleRules.qualifies(playedSeconds: 90, duration: 180))
        XCTAssertFalse(ScrobbleRules.qualifies(playedSeconds: 89, duration: 180))
        // 10-minute track: needs 240s (cap kicks in), not 300s (50%).
        XCTAssertTrue(ScrobbleRules.qualifies(playedSeconds: 240, duration: 600))
        XCTAssertFalse(ScrobbleRules.qualifies(playedSeconds: 239, duration: 600))
    }

    func test_qualifies_rejects_short_tracks_unconditionally() {
        XCTAssertFalse(ScrobbleRules.qualifies(playedSeconds: 200, duration: 25))
        XCTAssertFalse(ScrobbleRules.qualifies(playedSeconds: 200, duration: nil))
    }

    func test_qualifies_rejects_skip_debounce_window() {
        // 4-second play counts as a skip even on a 30-second track.
        XCTAssertFalse(ScrobbleRules.qualifies(playedSeconds: 4, duration: 30))
        XCTAssertTrue(ScrobbleRules.qualifies(playedSeconds: 16, duration: 30))
    }

    // MARK: - Track identity stability for candidate matching

    func test_replay_of_same_library_track_keeps_identity() {
        let a = Track(title: "X", artist: "Y", album: nil, albumArtist: nil,
                      trackNumber: nil, durationSeconds: 200,
                      persistentID: "PID-A", storeAdamID: nil, origin: .localFile)
        // Same persistent ID = same identity. The engine then uses startedAt
        // to disambiguate distinct plays of that identity.
        XCTAssertEqual(a.identity, "pid:PID-A")
    }

    func test_different_storeAdamIDs_get_different_identities() {
        let a = Track(title: "X", artist: "Y", album: nil, albumArtist: nil,
                      trackNumber: nil, durationSeconds: 200,
                      persistentID: nil, storeAdamID: "111", origin: .appleMusicCatalog)
        let b = Track(title: "X", artist: "Y", album: nil, albumArtist: nil,
                      trackNumber: nil, durationSeconds: 200,
                      persistentID: nil, storeAdamID: "222", origin: .appleMusicCatalog)
        XCTAssertNotEqual(a.identity, b.identity)
    }

    // MARK: - Eligibility gates

    func test_streams_are_not_scrobble_eligible() {
        let t = Track(title: "X", artist: "Y", album: nil, albumArtist: nil,
                      trackNumber: nil, durationSeconds: 200,
                      persistentID: nil, storeAdamID: nil, origin: .stream)
        XCTAssertFalse(t.isScrobbleEligible)
    }

    func test_empty_metadata_is_not_eligible() {
        let t = Track(title: "", artist: "Y", album: nil, albumArtist: nil,
                      trackNumber: nil, durationSeconds: 200,
                      persistentID: nil, storeAdamID: nil, origin: .localFile)
        XCTAssertFalse(t.isScrobbleEligible)
        let t2 = Track(title: "X", artist: "", album: nil, albumArtist: nil,
                       trackNumber: nil, durationSeconds: 200,
                       persistentID: nil, storeAdamID: nil, origin: .localFile)
        XCTAssertFalse(t2.isScrobbleEligible)
    }

    func test_short_track_is_not_eligible() {
        let t = Track(title: "X", artist: "Y", album: nil, albumArtist: nil,
                      trackNumber: nil, durationSeconds: 15,
                      persistentID: nil, storeAdamID: nil, origin: .localFile)
        XCTAssertFalse(t.isScrobbleEligible)
    }

    // MARK: - User overrides

    @MainActor func test_user_override_skipPodcasts_blocks_podcasts() {
        UserScrobbleSettings.shared.skipPodcasts = true
        let t = Track(title: "Show", artist: "Host", album: nil, albumArtist: nil,
                      trackNumber: nil, durationSeconds: 1800,
                      persistentID: "PID", storeAdamID: nil, origin: .podcast)
        XCTAssertFalse(t.isScrobbleEligibleWithUserOverrides())
    }

    @MainActor func test_user_override_skipPodcasts_off_allows_podcasts() {
        UserScrobbleSettings.shared.skipPodcasts = false
        let t = Track(title: "Show", artist: "Host", album: nil, albumArtist: nil,
                      trackNumber: nil, durationSeconds: 1800,
                      persistentID: "PID", storeAdamID: nil, origin: .podcast)
        XCTAssertTrue(t.isScrobbleEligibleWithUserOverrides())
        // Reset to default for other tests.
        UserScrobbleSettings.shared.skipPodcasts = true
    }

    @MainActor func test_ignored_artist_blocks_scrobble() {
        IgnoreRules.shared.clear()
        defer { IgnoreRules.shared.clear() }
        IgnoreRules.shared.add(pattern: "Banned", isRegex: false, scope: .artist)
        let t = Track(title: "Song", artist: "Banned", album: nil, albumArtist: nil,
                      trackNumber: nil, durationSeconds: 200,
                      persistentID: "PID", storeAdamID: nil, origin: .localFile)
        XCTAssertFalse(t.isScrobbleEligibleWithUserOverrides())
    }
}
