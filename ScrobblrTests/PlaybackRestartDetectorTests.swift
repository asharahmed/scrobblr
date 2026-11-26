import XCTest
@testable import Scrobblr

/// Pure tests for the playhead-wrap rule that catches repeat-one and
/// same-song replays, where Music never sends a stop between plays.
final class PlaybackRestartDetectorTests: XCTestCase {

    func test_repeatOneWrap_isDetected() {
        XCTAssertTrue(PlaybackRestartDetector.isRestart(
            previous: 209.6, new: 0.2, duration: 210, state: .playing
        ))
    }

    func test_sameSongQueuedTwice_isDetected() {
        // The poll catches the loop a second late; still the same wrap.
        XCTAssertTrue(PlaybackRestartDetector.isRestart(
            previous: 209.0, new: 1.4, duration: 210, state: .playing
        ))
    }

    func test_delayedPollAfterWrap_isDetected() {
        XCTAssertTrue(PlaybackRestartDetector.isRestart(
            previous: 205.0, new: 8.5, duration: 210, state: .playing
        ))
    }

    func test_shortTrackWrap_isDetected() {
        XCTAssertTrue(PlaybackRestartDetector.isRestart(
            previous: 29.5, new: 0.3, duration: 30, state: .playing
        ))
    }

    func test_normalProgress_isIgnored() {
        XCTAssertFalse(PlaybackRestartDetector.isRestart(
            previous: 100.0, new: 101.0, duration: 210, state: .playing
        ))
    }

    func test_forwardSeek_isIgnored() {
        XCTAssertFalse(PlaybackRestartDetector.isRestart(
            previous: 40.0, new: 180.0, duration: 210, state: .playing
        ))
    }

    func test_backwardSeekToMiddle_isIgnored() {
        XCTAssertFalse(PlaybackRestartDetector.isRestart(
            previous: 200.0, new: 120.0, duration: 210, state: .playing
        ))
    }

    func test_seekToStartBeforeHalfway_isIgnored() {
        // A restart only counts once the play passed the halfway point. A
        // scrub back to the top early in the track is still the same play.
        XCTAssertFalse(PlaybackRestartDetector.isRestart(
            previous: 60.0, new: 0.5, duration: 210, state: .playing
        ))
    }

    func test_exactlyHalfway_isIgnored() {
        XCTAssertFalse(PlaybackRestartDetector.isRestart(
            previous: 105.0, new: 0.5, duration: 210, state: .playing
        ))
    }

    func test_restartOutsideStartWindow_isIgnored() {
        // A pause at the end, a manual seek, and ten seconds of silence is
        // not the wrap we are looking for.
        XCTAssertFalse(PlaybackRestartDetector.isRestart(
            previous: 209.0, new: 10.5, duration: 210, state: .playing
        ))
    }

    func test_pausedState_isIgnored() {
        XCTAssertFalse(PlaybackRestartDetector.isRestart(
            previous: 209.6, new: 0.2, duration: 210, state: .paused
        ))
    }

    func test_stoppedState_isIgnored() {
        XCTAssertFalse(PlaybackRestartDetector.isRestart(
            previous: 209.6, new: 0.2, duration: 210, state: .stopped
        ))
    }

    func test_missingDuration_isIgnored() {
        XCTAssertFalse(PlaybackRestartDetector.isRestart(
            previous: 209.6, new: 0.2, duration: nil, state: .playing
        ))
    }

    func test_missingPreviousPosition_isIgnored() {
        XCTAssertFalse(PlaybackRestartDetector.isRestart(
            previous: nil, new: 0.2, duration: 210, state: .playing
        ))
    }

    func test_trackShorterThanLastFMFloor_isIgnored() {
        XCTAssertFalse(PlaybackRestartDetector.isRestart(
            previous: 19.5, new: 0.2, duration: 20, state: .playing
        ))
    }
}
