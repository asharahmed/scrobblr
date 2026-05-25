import Foundation

/// Last.fm-documented error codes we care about.
/// Full list: https://www.last.fm/api/errorcodes
enum LastFMError: Error, Equatable {
    case http(status: Int)
    case api(code: Int, message: String)
    case decoding(String)
    case missingCredentials
    case transport(String)

    /// Whether the caller should retry later, vs surface as a permanent failure.
    /// 11/16/29 are documented as transient; 9 demands re-auth (not a retry).
    var isTransient: Bool {
        switch self {
        case .http(let s) where (500...599).contains(s): return true
        case .http: return false
        case .api(let code, _):
            return code == 11 || code == 16 || code == 29
        case .transport: return true
        case .decoding, .missingCredentials: return false
        }
    }

    var requiresReauth: Bool {
        if case .api(let code, _) = self, code == 9 { return true }
        return false
    }
}
