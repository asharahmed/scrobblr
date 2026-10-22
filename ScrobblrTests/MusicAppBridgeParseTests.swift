import XCTest
@testable import Scrobblr

/// Regression tests for the AppleScript output parser. Issue #1: on locales
/// with a decimal comma, `real as text` produced "213,456", which failed to
/// parse, so every bridged track had no duration and never scrobbled.
final class MusicAppBridgeParseTests: XCTestCase {
    private func line(_ fields: [String]) -> String {
        fields.joined(separator: "\u{001F}")
    }

    func test_millisecond_fields_parse_to_seconds() {
        let snap = MusicAppBridge.parse(line([
            "playing", "61500", "Song", "Band", "Album", "", "213456", "3", "ABCDEF0123456789", "Apple Music AAC audio file",
        ]))
        XCTAssertEqual(snap?.state, .playing)
        XCTAssertEqual(snap?.position ?? 0, 61.5, accuracy: 0.001)
        XCTAssertEqual(snap?.track?.durationSeconds ?? 0, 213.456, accuracy: 0.001)
        XCTAssertEqual(snap?.track?.trackNumber, 3)
        XCTAssertEqual(snap?.track?.origin, .appleMusicCatalog)
    }

    func test_localized_decimal_comma_still_parses() {
        XCTAssertEqual(MusicAppBridge.seconds(fromMillis: "213456,0") ?? 0, 213.456, accuracy: 0.001)
        XCTAssertEqual(MusicAppBridge.seconds(fromMillis: "213456.0") ?? 0, 213.456, accuracy: 0.001)
    }

    func test_zero_duration_means_unknown() {
        let snap = MusicAppBridge.parse(line([
            "playing", "0", "Song", "Band", "", "", "0", "0", "", "",
        ]))
        XCTAssertNil(snap?.track?.durationSeconds)
    }

    func test_garbage_numbers_do_not_crash() {
        XCTAssertNil(MusicAppBridge.seconds(fromMillis: ""))
        XCTAssertNil(MusicAppBridge.seconds(fromMillis: "missing value"))
    }

    func test_wrong_field_count_is_rejected() {
        XCTAssertNil(MusicAppBridge.parse("playing\u{001F}0"))
    }
}
