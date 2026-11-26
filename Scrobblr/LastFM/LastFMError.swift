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

    /// 10 is an invalid API key, 26 a suspended one. Neither can be fixed by
    /// signing in again. Scrobblr ships its own key, so these mean the app
    /// key is gone and the user has to supply their own.
    var requiresAppKey: Bool {
        if case .api(let code, _) = self { return code == 10 || code == 26 }
        return false
    }
}

extension LastFMError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .http(let status):
            return "Last.fm returned HTTP \(status)."
        case .api(let code, let message):
            if code == 10 || code == 26 {
                return "Scrobblr's Last.fm key is unavailable. Add your own in Settings, Account, Advanced."
            }
            return message.isEmpty ? "Last.fm error \(code)." : message
        case .decoding:
            return "Last.fm sent an unexpected response."
        case .missingCredentials:
            return "No Last.fm session. Sign in again."
        case .transport(let message):
            return "Network error: \(message)"
        }
    }
}
