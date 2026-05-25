import XCTest
@testable import Scrobblr

final class ScrobbleRulesTests: XCTestCase {
    func test_tracksUnder30s_neverScrobble() {
        XCTAssertFalse(ScrobbleRules.qualifies(playedSeconds: 100, duration: 25))
        XCTAssertFalse(ScrobbleRules.qualifies(playedSeconds: 100, duration: nil))
    }

    func test_halfDurationRule() {
        // 200s track: needs 100s.
        XCTAssertFalse(ScrobbleRules.qualifies(playedSeconds: 99, duration: 200))
        XCTAssertTrue(ScrobbleRules.qualifies(playedSeconds: 100, duration: 200))
    }

    func test_fourMinuteCap_appliesToLongTracks() {
        // 10-min track: needs 240s, not 300s (half = 300, cap = 240, min wins).
        XCTAssertTrue(ScrobbleRules.qualifies(playedSeconds: 240, duration: 600))
        XCTAssertFalse(ScrobbleRules.qualifies(playedSeconds: 239, duration: 600))
    }

    func test_skipDebounce_belowFiveSeconds() {
        XCTAssertFalse(ScrobbleRules.qualifies(playedSeconds: 4, duration: 31))
    }
}
