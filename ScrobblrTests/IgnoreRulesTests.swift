import XCTest
@testable import Scrobblr

@MainActor
final class IgnoreRulesTests: XCTestCase {
    private var rules: IgnoreRules!

    override func setUp() {
        // Shared instance; clear between tests so we don't pollute each
        // other or the dev's stored Defaults.
        rules = IgnoreRules.shared
        rules.clear()
    }

    override func tearDown() {
        rules.clear()
    }

    func test_emptyRules_neverIgnore() {
        XCTAssertFalse(rules.shouldIgnoreArtist("Anything"))
        XCTAssertFalse(rules.shouldIgnoreTrack(artist: "x", title: "y"))
    }

    func test_exactArtistMatch_caseInsensitive() {
        rules.add(pattern: "Bad Artist", isRegex: false, scope: .artist)
        XCTAssertTrue(rules.shouldIgnoreArtist("Bad Artist"))
        XCTAssertTrue(rules.shouldIgnoreArtist("bad artist"))
        XCTAssertTrue(rules.shouldIgnoreArtist("BAD ARTIST"))
        XCTAssertFalse(rules.shouldIgnoreArtist("Good Artist"))
    }

    func test_artistRule_alsoMatchesTrackScope() {
        rules.add(pattern: "Skippy", isRegex: false, scope: .artist)
        XCTAssertTrue(rules.shouldIgnoreTrack(artist: "Skippy", title: "Whatever"))
        XCTAssertFalse(rules.shouldIgnoreTrack(artist: "Other", title: "Whatever"))
    }

    func test_substring_in_exactMode_matches() {
        // Exact mode is documented as "contains". we use range(of:) which
        // matches substrings case-insensitively.
        rules.add(pattern: "remix", isRegex: false, scope: .track)
        XCTAssertTrue(rules.shouldIgnoreTrack(artist: "Whoever", title: "Song (Remix)"))
        XCTAssertFalse(rules.shouldIgnoreTrack(artist: "Whoever", title: "Original"))
    }

    func test_regex_anchored() {
        rules.add(pattern: "^DJ ", isRegex: true, scope: .artist)
        XCTAssertTrue(rules.shouldIgnoreArtist("DJ Shadow"))
        XCTAssertFalse(rules.shouldIgnoreArtist("Old DJ Stuff"))
    }

    func test_invalid_regex_doesNotMatch_doesNotCrash() {
        rules.add(pattern: "(unbalanced", isRegex: true, scope: .artist)
        XCTAssertFalse(rules.shouldIgnoreArtist("(unbalanced"))
    }

    func test_duplicateAdd_isNoop() {
        rules.add(pattern: "x", isRegex: false, scope: .artist)
        rules.add(pattern: "x", isRegex: false, scope: .artist)
        XCTAssertEqual(rules.rules.count, 1)
    }

    func test_remove_byId() {
        rules.add(pattern: "a", isRegex: false, scope: .artist)
        rules.add(pattern: "b", isRegex: false, scope: .artist)
        guard let first = rules.rules.first else { return XCTFail("empty") }
        rules.remove(id: first.id)
        XCTAssertEqual(rules.rules.count, 1)
        XCTAssertEqual(rules.rules.first?.pattern, "b")
    }
}
