import XCTest
@testable import Scrobblr

/// LastFMError classification. guards the auth poll's success / pending /
/// tokenDead / transient distinction. Catching the wrong category was the
/// original "infinite-loop on token expiry" bug.
final class LastFMErrorClassificationTests: XCTestCase {
    func test_code9_requiresReauth() {
        XCTAssertTrue(LastFMError.api(code: 9, message: "invalid session").requiresReauth)
    }

    func test_otherCodes_doNotRequireReauth() {
        XCTAssertFalse(LastFMError.api(code: 14, message: "").requiresReauth)
        XCTAssertFalse(LastFMError.api(code: 4, message: "").requiresReauth)
    }

    func test_transient_codes() {
        XCTAssertTrue(LastFMError.api(code: 11, message: "").isTransient)
        XCTAssertTrue(LastFMError.api(code: 16, message: "").isTransient)
        XCTAssertTrue(LastFMError.api(code: 29, message: "").isTransient)
        XCTAssertFalse(LastFMError.api(code: 6, message: "").isTransient)
    }

    func test_http5xx_isTransient() {
        XCTAssertTrue(LastFMError.http(status: 500).isTransient)
        XCTAssertTrue(LastFMError.http(status: 503).isTransient)
        XCTAssertFalse(LastFMError.http(status: 400).isTransient)
    }
}
