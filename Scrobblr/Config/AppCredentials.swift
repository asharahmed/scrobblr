import Foundation

/// Last.fm application credentials owned by Scrobblr itself.
///
/// From 1 December 2026 Last.fm only accepts API keys whose owner has an
/// active Pro subscription. Asking every user to register their own key is
/// therefore no longer a viable onboarding path, so the app ships the
/// project's own key and users simply sign in through Last.fm's browser
/// approval page (desktop auth).
///
/// The values are injected at build time from Xcode build settings, which
/// the release script reads out of a gitignored `AppKey.local.xcconfig`.
/// They still end up inside the shipped binary: that is unavoidable for a
/// desktop client, and Last.fm treats the API key as public by design (it
/// appears verbatim in the authorization URL). Keeping the pair out of git
/// only stops the repository itself from acting as a public key registry.
///
/// A user can still supply their own key in Settings → Account → Advanced;
/// `Credentials` prefers that override when present.
enum AppCredentials {
    /// Scrobblr's Last.fm API key, or nil when the build was produced
    /// without one (local Debug builds, forks).
    static var apiKey: String? { resolved(infoKey: "LastFMAppAPIKey", debugValue: debugAPIKey) }

    /// Scrobblr's Last.fm shared secret, paired with `apiKey`.
    static var sharedSecret: String? { resolved(infoKey: "LastFMAppSharedSecret", debugValue: debugSharedSecret) }

    /// True when both halves of the pair made it into this build.
    static var isConfigured: Bool { apiKey != nil && sharedSecret != nil }

    /// Debug-only convenience values from `Secrets.swift`. The `Secrets`
    /// symbol does not exist in Release builds.
    static var debugAPIKey: String? {
        #if DEBUG
        return Secrets.lastFMAPIKey
        #else
        return nil
        #endif
    }

    static var debugSharedSecret: String? {
        #if DEBUG
        return Secrets.lastFMSharedSecret
        #else
        return nil
        #endif
    }

    private static func resolved(infoKey: String, debugValue: String?) -> String? {
        let raw = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String
        return valid(raw) ?? valid(debugValue)
    }

    /// Last.fm keys and secrets are 32 hexadecimal characters. Anything
    /// else (an unexpanded `$(LASTFM_APP_API_KEY)` build setting, an empty
    /// string, a pasted placeholder) is treated as absent so the app falls
    /// back to the per-user key step instead of failing at sign-in.
    static func valid(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.count == 32,
              value.allSatisfy({ $0.isHexDigit })
        else { return nil }
        return value
    }
}
