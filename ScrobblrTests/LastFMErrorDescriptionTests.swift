import XCTest
@testable import Scrobblr

/// User-facing text for Last.fm failures, especially the app-key case.
final class LastFMErrorDescriptionTests: XCTestCase {

    func test_invalidAppKey_pointsAtSettingsOverride() {
        let message = LastFMError.api(code: 10, message: "Invalid API key").localizedDescription
        XCTAssertTrue(message.contains("Settings, Account, Advanced"))
        XCTAssertTrue(message.contains("key is unavailable"))
    }

    func test_suspendedAppKey_pointsAtSettingsOverride() {
        let message = LastFMError.api(code: 26, message: "Suspended API key").localizedDescription
        XCTAssertTrue(message.contains("Settings, Account, Advanced"))
    }

    func test_otherAPIError_usesServerMessage() {
        XCTAssertEqual(
            LastFMError.api(code: 6, message: "Invalid resource specified").localizedDescription,
            "Invalid resource specified"
        )
    }

    func test_emptyAPIError_includesCode() {
        XCTAssertEqual(
            LastFMError.api(code: 6, message: "").localizedDescription,
            "Last.fm error 6."
        )
    }

    func test_missingSession_tellsUserToSignIn() {
        XCTAssertTrue(LastFMError.missingCredentials.localizedDescription.contains("Sign in again"))
    }

    func test_requiresAppKey_coversInvalidAndSuspended() {
        XCTAssertTrue(LastFMError.api(code: 10, message: "").requiresAppKey)
        XCTAssertTrue(LastFMError.api(code: 26, message: "").requiresAppKey)
        XCTAssertFalse(LastFMError.api(code: 9, message: "").requiresAppKey)
        XCTAssertFalse(LastFMError.api(code: 29, message: "").requiresAppKey)
    }
}
