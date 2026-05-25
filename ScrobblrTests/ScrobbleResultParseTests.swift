import XCTest
@testable import Scrobblr

/// Exercises the `ScrobbleAcceptance.disposition` mapping that drives
/// whether records get acknowledged, dropped, or retried.
final class ScrobbleResultParseTests: XCTestCase {
    func test_acceptedDisposition() {
        let a = ScrobbleAcceptance.accepted
        XCTAssertEqual(a.disposition, .acknowledge)
        XCTAssertTrue(a.isAccepted)
    }

    func test_artistFiltered_code1_drops() {
        let a = ScrobbleAcceptance.ignored(code: 1, message: "")
        XCTAssertEqual(a.disposition, .drop)
        XCTAssertFalse(a.isAccepted)
    }

    func test_timestampTooOld_code3_drops() {
        XCTAssertEqual(ScrobbleAcceptance.ignored(code: 3, message: "").disposition, .drop)
    }

    func test_timestampTooNew_code4_retries() {
        XCTAssertEqual(ScrobbleAcceptance.ignored(code: 4, message: "").disposition, .retryLater)
    }

    func test_dailyLimit_code5_pausesDay() {
        XCTAssertEqual(ScrobbleAcceptance.ignored(code: 5, message: "").disposition, .pauseDay)
    }

    func test_unknownCode_drops() {
        XCTAssertEqual(ScrobbleAcceptance.ignored(code: 99, message: "").disposition, .drop)
    }
}
