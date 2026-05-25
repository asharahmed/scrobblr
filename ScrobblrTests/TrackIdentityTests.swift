import XCTest
@testable import Scrobblr

/// Regression tests for `Track.identity`. Two distinct catalog recordings
/// must NOT collide on identity when they happen to share artist/album/
/// title/duration. the previous fallback would have folded them.
final class TrackIdentityTests: XCTestCase {
    func test_persistentID_wins() {
        let t = Track(title: "x", artist: "y", album: nil, albumArtist: nil,
                      trackNumber: nil, durationSeconds: 100,
                      persistentID: "ABCDEF", storeAdamID: nil, origin: .localFile)
        XCTAssertEqual(t.identity, "pid:ABCDEF")
    }

    func test_adamID_falls_through_to_second_priority() {
        let t = Track(title: "x", artist: "y", album: nil, albumArtist: nil,
                      trackNumber: nil, durationSeconds: 100,
                      persistentID: nil, storeAdamID: "12345", origin: .appleMusicCatalog)
        XCTAssertEqual(t.identity, "adam:12345")
    }

    func test_emptyPersistentID_isSkipped() {
        // Empty string used to produce "pid:". now treated as missing.
        let t = Track(title: "x", artist: "y", album: nil, albumArtist: nil,
                      trackNumber: nil, durationSeconds: 100,
                      persistentID: "", storeAdamID: "99", origin: .appleMusicCatalog)
        XCTAssertEqual(t.identity, "adam:99")
    }

    func test_tuple_includes_origin_so_local_vs_catalog_differ() {
        let local = Track(title: "Song", artist: "Band", album: "Alb", albumArtist: nil,
                          trackNumber: nil, durationSeconds: 200,
                          persistentID: nil, storeAdamID: nil, origin: .localFile)
        let stream = Track(title: "Song", artist: "Band", album: "Alb", albumArtist: nil,
                           trackNumber: nil, durationSeconds: 200,
                           persistentID: nil, storeAdamID: nil, origin: .appleMusicCatalog)
        XCTAssertNotEqual(local.identity, stream.identity)
    }

    func test_tuple_caseInsensitive() {
        let a = Track(title: "FOO", artist: "BAR", album: "BAZ", albumArtist: nil,
                      trackNumber: nil, durationSeconds: 100,
                      persistentID: nil, storeAdamID: nil, origin: .localFile)
        let b = Track(title: "foo", artist: "bar", album: "baz", albumArtist: nil,
                      trackNumber: nil, durationSeconds: 100,
                      persistentID: nil, storeAdamID: nil, origin: .localFile)
        XCTAssertEqual(a.identity, b.identity)
    }
}
