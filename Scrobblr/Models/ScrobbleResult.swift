import Foundation

/// What Last.fm did with each record we submitted. Decoded from
/// `scrobbles.scrobble[*].ignoredMessage.code` in `track.scrobble`.
///
/// 0   accepted
/// 1   artist/track was ignored
/// 2   artist+track filtered
/// 3   timestamp too old (more than ~2 weeks)
/// 4   timestamp too new (clock skew)
/// 5   daily scrobble limit exceeded
public enum ScrobbleAcceptance: Sendable, Equatable {
    case accepted
    case ignored(code: Int, message: String)

    var isAccepted: Bool {
        if case .accepted = self { return true }
        return false
    }

    /// Should the record be permanently dropped (no point retrying), vs paused
    /// briefly (daily limit), vs cleared from the queue with a warning?
    var disposition: Disposition {
        switch self {
        case .accepted: return .acknowledge
        case .ignored(let code, _):
            switch code {
            case 1, 2, 3: return .drop      // permanent — drop the record
            case 4:       return .retryLater // clock skew — wait, then retry
            case 5:       return .pauseDay  // daily limit — pause flush
            default:      return .drop
            }
        }
    }

    enum Disposition { case acknowledge, drop, retryLater, pauseDay }
}

/// Per-record outcome zipped with the submitted record id.
public struct ScrobbleResult: Sendable {
    public let id: UUID
    public let acceptance: ScrobbleAcceptance
}
