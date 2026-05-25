import Foundation
import CryptoKit

/// Computes the `api_sig` Last.fm requires on signed calls.
///
/// Algorithm (per https://www.last.fm/api/authspec):
///   1. Take every request parameter EXCEPT `format` and `callback`.
///   2. Sort the parameter names lexicographically.
///      NB: `artist[10]` < `artist[2]` in lex order. We sort the literal
///      bracketed names, not the integer indices.
///   3. Concatenate as <name1><value1><name2><value2>… (no separators).
///   4. Append the shared secret.
///   5. md5(UTF-8 bytes of the concatenation) → 32-char lowercase hex.
enum LastFMSignature {
    static func sign(_ params: [String: String], secret: String) -> String {
        var buf = ""
        let keys = params.keys.sorted()
        for k in keys {
            if k == "format" || k == "callback" { continue }
            buf.append(k)
            buf.append(params[k] ?? "")
        }
        buf.append(secret)
        let digest = Insecure.MD5.hash(data: Data(buf.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
