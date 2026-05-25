import Foundation
import os

/// Centralised loggers. Use os.Logger so messages flow to Console.app with
/// proper subsystem/category filtering. invaluable when diagnosing a shipped
/// build with `log stream --predicate 'subsystem == "app.scrobblr"'`.
enum Log {
    static let playback = Logger(subsystem: "app.scrobblr", category: "playback")
    static let scrobble = Logger(subsystem: "app.scrobblr", category: "scrobble")
    static let api      = Logger(subsystem: "app.scrobblr", category: "api")
    static let auth     = Logger(subsystem: "app.scrobblr", category: "auth")
    static let lifecycle = Logger(subsystem: "app.scrobblr", category: "lifecycle")
}
