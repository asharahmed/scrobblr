import Foundation
import Combine

/// Bring-Your-Own-Key store for Last.fm API credentials.
///
/// Last.fm doesn't issue per-app keys that are safe to bake into a publicly-
/// distributed binary — anyone with the .app can strip the shared secret and
/// abuse it, after which Last.fm bans the key and every user breaks. So
/// Scrobblr asks each user to register their own application at
/// `https://www.last.fm/api/account/create` and paste the key + secret here.
///
/// Storage: macOS Keychain (`apiKey`, `sharedSecret` accounts under service
/// `app.scrobblr.Scrobblr`). Reading is synchronous; the published flag
/// `isConfigured` lets SwiftUI react to (re)entry.
///
/// Dev override: in DEBUG builds we accept seeds from a `Secrets.swift`
/// scaffolded by `bootstrap.sh`. The file is gitignored AND the entire
/// `Secrets` enum is wrapped in `#if DEBUG` so it never reaches the
/// shipped binary.
@MainActor
final class Credentials: ObservableObject {
    static let shared = Credentials()

    @Published private(set) var apiKey: String?
    @Published private(set) var sharedSecret: String?

    init() {
        self.apiKey = Keychain.get("apiKey")
        self.sharedSecret = Keychain.get("sharedSecret")

        #if DEBUG
        // Dev convenience: if the developer has a Secrets.swift with real
        // values and the Keychain is empty, seed once. Production builds
        // never compile this branch.
        if (apiKey == nil || sharedSecret == nil),
           let devKey = Secrets.lastFMAPIKey, !devKey.isEmpty, devKey != "REPLACE_ME",
           let devSecret = Secrets.lastFMSharedSecret, !devSecret.isEmpty, devSecret != "REPLACE_ME" {
            try? store(apiKey: devKey, sharedSecret: devSecret)
        }
        #endif
    }

    var isConfigured: Bool {
        guard let k = apiKey, !k.isEmpty else { return false }
        guard let s = sharedSecret, !s.isEmpty else { return false }
        return true
    }

    func store(apiKey: String, sharedSecret: String) throws {
        try Keychain.set(apiKey, for: "apiKey")
        try Keychain.set(sharedSecret, for: "sharedSecret")
        self.apiKey = apiKey
        self.sharedSecret = sharedSecret
    }

    func clear() {
        Keychain.delete("apiKey")
        Keychain.delete("sharedSecret")
        self.apiKey = nil
        self.sharedSecret = nil
    }
}
