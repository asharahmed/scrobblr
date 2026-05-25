import XCTest
import CryptoKit
@testable import Scrobblr

final class LastFMSignatureTests: XCTestCase {
    func test_excludesFormatAndCallback_sortsParams() {
        let sig = LastFMSignature.sign(
            ["method": "auth.getToken", "api_key": "xxx", "format": "json", "callback": "cb"],
            secret: "secret"
        )
        // Concatenation should be: api_keyxxxmethodauth.getTokensecret
        XCTAssertEqual(sig, md5Hex("api_keyxxxmethodauth.getTokensecret"))
    }

    func test_bracketedKeys_sortLexicographically_not_numerically() {
        // Lex order: artist[10] < artist[2]. This is the Last.fm-correct order.
        let sig = LastFMSignature.sign(
            ["artist[2]": "B", "artist[10]": "A"],
            secret: "s"
        )
        XCTAssertEqual(sig, md5Hex("artist[10]Aartist[2]Bs"))
    }

    func test_unicodeValues_signedAsUTF8() {
        let sig = LastFMSignature.sign(
            ["artist": "Sigur Rós", "track": "Hoppípolla"],
            secret: "k"
        )
        XCTAssertEqual(sig, md5Hex("artistSigur RóstrackHoppípollak"))
    }

    private func md5Hex(_ s: String) -> String {
        Insecure.MD5.hash(data: Data(s.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}
