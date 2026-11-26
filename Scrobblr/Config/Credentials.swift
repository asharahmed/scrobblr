import Foundation
import Combine

/// Resolves the Last.fm application credentials the client should use.
///
/// Two sources, in priority order:
///
/// 1. A per-user override in the Keychain, entered in Settings → Account →
///    Advanced. This is the escape hatch if Scrobblr's shipped key ever stops
///    working, and what forks use.
/// 2. `AppCredentials`, the project's own key injected at build time. This is
///    the normal path: users sign in through Last.fm's browser approval page
///    and never touch an API key.
///
/// Since Last.fm started requiring Pro to own an API key, a build with only
/// per-user credentials cannot onboard free users, so onboarding asks for a
/// key only when `AppCredentials` is absent.
///
/// Storage: macOS Keychain (`apiKey`, `sharedSecret` accounts under service
/// `app.scrobblr.Scrobblr`). Reading is synchronous; the published flags let
/// SwiftUI react to (re)entry.
@MainActor
final class Credentials: ObservableObject {
    static let shared = Credentials()

    /// User-supplied override. Both are nil when Scrobblr's key is in use.
    @Published private(set) var overrideAPIKey: String?
    @Published private(set) var overrideSharedSecret: String?

    /// Effective credentials handed to `LastFMClient`.
    @Published private(set) var apiKey: String?
    @Published private(set) var sharedSecret: String?

    /// True when a stored per-user key was discarded at launch because this
    /// build carries Scrobblr's own credentials. `AppCoordinator` uses it to
    /// drop the session key that was issued against the old application.
    let didDropStoredOverride: Bool

    private static let migrationFlag = "migratedToAppCredentials"

    init() {
        #if DEBUG
        // Dev convenience: seed from a Secrets.swift with real values on a
        // fresh Keychain. Skip it when the app already has its own key, so
        // the debug build exercises the same path as a release.
        if !AppCredentials.isConfigured,
           Keychain.get("apiKey") == nil, Keychain.get("sharedSecret") == nil,
           let devKey = AppCredentials.valid(AppCredentials.debugAPIKey),
           let devSecret = AppCredentials.valid(AppCredentials.debugSharedSecret) {
            try? Keychain.set(devKey, for: "apiKey")
            try? Keychain.set(devSecret, for: "sharedSecret")
        }
        #endif

        var storedKey = Keychain.get("apiKey")
        var storedSecret = Keychain.get("sharedSecret")

        // A half-written pair is unusable; treat it as absent.
        if storedKey == nil || storedSecret == nil {
            Keychain.delete("apiKey")
            Keychain.delete("sharedSecret")
            storedKey = nil
            storedSecret = nil
        }

        // One-time migration: builds that ship Scrobblr's key stop using the
        // per-user key people registered under the old BYOK flow. Those keys
        // require Last.fm Pro from 1 December 2026, so leaving them in place
        // breaks the app for everyone who upgraded. Users can add their own
        // key again afterwards.
        var dropped = false
        if AppCredentials.isConfigured,
           !UserDefaults.standard.bool(forKey: Self.migrationFlag),
           storedKey != nil || storedSecret != nil {
            Keychain.delete("apiKey")
            Keychain.delete("sharedSecret")
            storedKey = nil
            storedSecret = nil
            dropped = true
        }
        if AppCredentials.isConfigured {
            UserDefaults.standard.set(true, forKey: Self.migrationFlag)
        }

        self.overrideAPIKey = storedKey
        self.overrideSharedSecret = storedSecret
        self.didDropStoredOverride = dropped
        self.apiKey = storedKey ?? AppCredentials.apiKey
        self.sharedSecret = storedSecret ?? AppCredentials.sharedSecret

        if dropped {
            Log.lifecycle.info("discarded per-user API key in favour of the app key")
        }
    }

    /// Whether this build carries Scrobblr's own Last.fm application key.
    static var hasBuiltIn: Bool { AppCredentials.isConfigured }

    /// True when the effective key came from the app rather than the user.
    var isUsingBuiltIn: Bool { overrideAPIKey == nil && AppCredentials.isConfigured }

    /// True when the user supplied their own key.
    var isUsingOverride: Bool { overrideAPIKey != nil }

    var isConfigured: Bool {
        guard let k = apiKey, !k.isEmpty else { return false }
        guard let s = sharedSecret, !s.isEmpty else { return false }
        return true
    }

    /// Store a user override. Kept for self-hosted builds and as an escape
    /// hatch if the shipped key is ever revoked.
    func store(apiKey: String, sharedSecret: String) throws {
        try Keychain.set(apiKey, for: "apiKey")
        try Keychain.set(sharedSecret, for: "sharedSecret")
        self.overrideAPIKey = apiKey
        self.overrideSharedSecret = sharedSecret
        resolve()
    }

    /// Drop the user override and return to Scrobblr's own key.
    func clearOverride() {
        Keychain.delete("apiKey")
        Keychain.delete("sharedSecret")
        self.overrideAPIKey = nil
        self.overrideSharedSecret = nil
        resolve()
    }

    private func resolve() {
        self.apiKey = overrideAPIKey ?? AppCredentials.apiKey
        self.sharedSecret = overrideSharedSecret ?? AppCredentials.sharedSecret
    }
}
