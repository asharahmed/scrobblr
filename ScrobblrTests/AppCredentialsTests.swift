import XCTest
@testable import Scrobblr

final class AppCredentialsTests: XCTestCase {
    func test_accepts32HexCharacters() {
        XCTAssertEqual(
            AppCredentials.valid("0123456789abcdef0123456789abcdef"),
            "0123456789abcdef0123456789abcdef"
        )
    }

    func test_trimsSurroundingWhitespace() {
        XCTAssertEqual(
            AppCredentials.valid("  0123456789ABCDEF0123456789abcdef\n"),
            "0123456789ABCDEF0123456789abcdef"
        )
    }

    func test_rejectsUnresolvedBuildSetting() {
        XCTAssertNil(AppCredentials.valid("$" + "(LASTFM_APP_API_KEY)"))
    }

    func test_rejectsEmptyAndPlaceholder() {
        XCTAssertNil(AppCredentials.valid(nil))
        XCTAssertNil(AppCredentials.valid(""))
        XCTAssertNil(AppCredentials.valid("REPLACE_ME"))
    }

    func test_rejectsWrongLengthOrNonHex() {
        XCTAssertNil(AppCredentials.valid("0123456789abcdef"))
        XCTAssertNil(AppCredentials.valid("0123456789abcdef0123456789abcdeg"))
    }
}
