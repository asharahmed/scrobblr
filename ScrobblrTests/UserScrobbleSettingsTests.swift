import XCTest
@testable import Scrobblr

/// Custom-threshold path through ScrobbleRules + pause-state semantics.
@MainActor
final class UserScrobbleSettingsTests: XCTestCase {

    // MARK: - ScrobbleRules with overridden thresholds

    func test_defaultThresholds_unchangedBehavior() {
        // 200s track, played 100s → qualifies at exactly 50%.
        XCTAssertTrue(ScrobbleRules.qualifies(playedSeconds: 100, duration: 200))
        XCTAssertFalse(ScrobbleRules.qualifies(playedSeconds: 99, duration: 200))
    }

    func test_customPercent_25_lowersBar() {
        XCTAssertTrue(ScrobbleRules.qualifies(playedSeconds: 50, duration: 200,
                                              thresholdPercent: 0.25))
        XCTAssertFalse(ScrobbleRules.qualifies(playedSeconds: 49, duration: 200,
                                               thresholdPercent: 0.25))
    }

    func test_customPercent_90_raisesBar() {
        XCTAssertFalse(ScrobbleRules.qualifies(playedSeconds: 100, duration: 200,
                                               thresholdPercent: 0.9))
        XCTAssertTrue(ScrobbleRules.qualifies(playedSeconds: 180, duration: 200,
                                              thresholdPercent: 0.9))
    }

    func test_customSeconds_60_capsLongTracks() {
        // 10-min track: min(60, 600*0.5=300) = 60.
        XCTAssertTrue(ScrobbleRules.qualifies(playedSeconds: 60, duration: 600,
                                              thresholdSeconds: 60))
        XCTAssertFalse(ScrobbleRules.qualifies(playedSeconds: 59, duration: 600,
                                               thresholdSeconds: 60))
    }

    func test_skipDebounceUnaffectedByThresholds() {
        XCTAssertFalse(ScrobbleRules.qualifies(playedSeconds: 4, duration: 200,
                                               thresholdSeconds: 1,
                                               thresholdPercent: 0.01))
    }

    // MARK: - Pause semantics

    func test_pauseFor_setsFutureDate_andIsPaused() {
        let s = UserScrobbleSettings.shared
        s.resume()
        XCTAssertFalse(s.isPaused)
        s.pauseFor(300)
        XCTAssertTrue(s.isPaused)
        XCTAssertNotNil(s.pauseUntil)
        s.resume()
        XCTAssertFalse(s.isPaused)
    }

    func test_pauseIndefinitely_setsDistantFuture() {
        let s = UserScrobbleSettings.shared
        s.pauseIndefinitely()
        XCTAssertEqual(s.pauseUntil, .distantFuture)
        XCTAssertTrue(s.isPaused)
        s.resume()
    }

    func test_resume_clearsPause() {
        let s = UserScrobbleSettings.shared
        s.pauseFor(60)
        s.resume()
        XCTAssertNil(s.pauseUntil)
        XCTAssertFalse(s.isPaused)
    }
}
