import SwiftUI
import AppKit
import Combine

/// MenuBarExtra label. The label view is mounted *eagerly* at scene-build
/// time (it has to render the status bar icon at launch). MenuBarExtra
/// content, in contrast, is lazy and not instantiated until the user clicks
/// the icon. so any logic that must run at launch (e.g. opening the welcome
/// window) attaches here.
private struct MenuBarLabel: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: coordinator.menuBarSymbol)
            .symbolEffect(
                .variableColor.iterative.reversing,
                options: .repeating,
                isActive: coordinator.observer.snapshot.state == .playing
            )
            .contentTransition(.symbolEffect(.replace.downUp))
            .onChange(of: coordinator.welcomeOpenRequest) { _, new in
                guard new != nil else { return }
                openWindow(id: "welcome")
            }
            .onChange(of: coordinator.statsOpenRequest) { _, new in
                guard new != nil else { return }
                openWindow(id: "stats")
            }
            .onAppear {
                // First-launch: open Welcome if onboarding hasn't been done.
                // We do this in onAppear so it survives even if the bootstrap
                // assignment in AppCoordinator.init races scene construction.
                if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                    DispatchQueue.main.async {
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: "welcome")
                    }
                }
            }
    }
}

@main
struct ScrobblrApp: App {
    @StateObject private var coordinator = AppCoordinator()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(coordinator)
        } label: {
            MenuBarLabel()
                .environmentObject(coordinator)
        }
        .menuBarExtraStyle(.window)

        Window("Welcome to Scrobblr", id: "welcome") {
            WelcomeView(coordinator: coordinator)
                .environmentObject(coordinator)
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)
        .defaultPosition(.center)

        Window("Stats", id: "stats") {
            StatsView(coordinator: coordinator)
                .environmentObject(coordinator)
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .environmentObject(coordinator)
                .frame(minWidth: 720, minHeight: 520, idealHeight: 580)
        }
    }
}

/// The single owner of the long-lived objects. Wires the observer, the
/// Last.fm client, and the scrobble engine together at launch.
@MainActor
final class AppCoordinator: ObservableObject {
    let observer = PlaybackObserver()
    let queue = ScrobbleQueue()
    let client: LastFMClient
    let engine: ScrobbleEngine
    let monitor = SystemMonitor()
    let loginItem = LoginItem.shared
    let credentials = Credentials.shared

    @Published var username: String? = Keychain.get("username")
    @Published var isAuthenticated: Bool
    @Published var welcomeOpenRequest: UUID? = nil
    @Published var statsOpenRequest: UUID? = nil

    // Forward nested ObservableObject changes (observer.snapshot, engine.*)
    // up so SwiftUI views that observe `coordinator` re-render. Without this,
    // updates inside observer/engine don't propagate because @StateObject only
    // subscribes to coordinator's own objectWillChange.
    private var forwarders: Set<AnyCancellable> = []

    /// Last.fm API key that issued the stored session key. Lets us discard
    /// sessions after the app switches applications.
    private static let sessionAPIKeyDefaultsKey = "sessionAPIKey"

    init() {
        // Credentials first: constructing it can migrate a stored per-user
        // key away in favour of the app's own key, which invalidates the
        // session.
        let creds = Credentials.shared
        var sk = Keychain.get("sessionKey")

        // A session key is issued to one Last.fm application. When the
        // effective key changes (first run on a build with the app key, or
        // the user switching to their own key and back), the stored session
        // no longer applies. Drop it so the UI asks for a fresh sign-in.
        let issuingKey = UserDefaults.standard.string(forKey: Self.sessionAPIKeyDefaultsKey)
        let droppedSession = sk != nil
            && (creds.didDropStoredOverride || (issuingKey != nil && issuingKey != creds.apiKey))
        if droppedSession {
            Keychain.delete("sessionKey")
            Keychain.delete("username")
            UserDefaults.standard.removeObject(forKey: Self.sessionAPIKeyDefaultsKey)
            sk = nil
            Log.lifecycle.info("dropped session key issued to a different application")
        }

        // The client tolerates empty credentials so the app can still launch
        // and explain what is missing; auth/scrobble calls surface an error
        // the UI routes back to the credential step.
        let c = LastFMClient(
            apiKey: creds.apiKey ?? "",
            sharedSecret: creds.sharedSecret ?? "",
            sessionKey: sk
        )
        self.client = c
        self.engine = ScrobbleEngine(observer: observer, client: c, queue: queue, monitor: monitor)
        // We're "authenticated" only if BOTH a session key exists AND
        // we have credentials to make API calls. Otherwise the session is
        // useless until the user provides a key.
        self.isAuthenticated = (sk != nil) && creds.isConfigured
        if droppedSession { self.username = nil }

        monitor.start()

        // Install Last.fm artwork fallback so ArtworkFetcher can ask
        // track.getInfo when iTunes Search misses a track.
        ArtworkFetcher.lastFMArtworkLookup = { [client = self.client] artist, title in
            await client.trackInfoArtworkURL(artist: artist, title: title)
        }
        observer.start()
        engine.start()

        if AutomationPermission.status(forBundleID: "com.apple.Music") == .granted {
            observer.enablePlaybackPolling()
        }

        Log.lifecycle.info("Scrobblr launched; authed=\(self.isAuthenticated, privacy: .public)")

        observer.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &forwarders)
        engine.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &forwarders)
        UserScrobbleSettings.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &forwarders)
        IgnoreRules.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &forwarders)

        // Cancel inflight work on app termination.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.shutdown() }
        }
    }

    func shutdown() {
        Log.lifecycle.info("shutdown")
        engine.stop()
        observer.stop()
        monitor.stop()
    }

    /// Store a user-supplied Last.fm key, push it into the running client,
    /// and clear the stale session key (it was issued against a different
    /// application). This is the Advanced escape hatch; the normal path is
    /// the app's own key.
    func setCredentials(apiKey: String, sharedSecret: String) throws {
        try credentials.store(apiKey: apiKey, sharedSecret: sharedSecret)
        let key = apiKey
        let secret = sharedSecret
        Task { await client.updateCredentials(apiKey: key, sharedSecret: secret) }
        invalidateSession()
        engine.requestFlushNow()
        Log.lifecycle.info("user API credentials updated")
    }

    /// Drop the user-supplied key and go back to Scrobblr's own application
    /// key. Signs the user out because the session belonged to the old app.
    func useAppCredentials() {
        guard Credentials.hasBuiltIn,
              let key = AppCredentials.apiKey, let secret = AppCredentials.sharedSecret
        else {
            Log.lifecycle.info("no app credentials in this build")
            return
        }
        credentials.clearOverride()
        Task { await client.updateCredentials(apiKey: key, sharedSecret: secret) }
        invalidateSession()
        engine.requestFlushNow()
        Log.lifecycle.info("reverted to app credentials")
    }

    /// Forget the current Last.fm session. The next API call surfaces a
    /// re-auth prompt rather than failing silently.
    private func invalidateSession() {
        Keychain.delete("sessionKey")
        Keychain.delete("username")
        UserDefaults.standard.removeObject(forKey: Self.sessionAPIKeyDefaultsKey)
        Task { await client.setSessionKey(nil) }
        username = nil
        isAuthenticated = false
    }

    /// Called by OnboardingViewModel.finish(). closes the welcome window.
    func didFinishOnboarding() {
        Log.lifecycle.info("onboarding completed")
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "welcome" }) {
            window.close()
        }
    }

    /// Re-open the welcome window from a menu / settings action (lets the
    /// user revisit onboarding if they previously skipped a step).
    func showWelcome() {
        welcomeOpenRequest = UUID()
    }

    /// Open the Stats window from the menu bar.
    func showStats() {
        NSApp.activate(ignoringOtherApps: true)
        statsOpenRequest = UUID()
    }

    var menuBarSymbol: String {
        if !isAuthenticated { return "waveform.slash" }
        if engine.needsReauth { return "exclamationmark.triangle" }
        if UserScrobbleSettings.shared.isPaused { return "waveform.badge.minus" }
        switch observer.snapshot.state {
        case .playing:
            return observer.snapshot.track?.origin == .stream ? "antenna.radiowaves.left.and.right" : "waveform"
        case .paused: return "pause.circle"
        case .stopped:
            // If Last.fm reports the user is playing on another device,
            // reflect that in the menu bar so the icon isn't misleadingly
            // static while their iPhone or web player scrobbles away.
            if engine.remoteNowPlaying != nil { return "wave.3.right" }
            return "waveform.circle"
        }
    }

    // MARK: - Auth

    @Published var authToken: String?
    @Published var authError: String?
    @Published var authPhase: AuthPhase = .idle
    private var authPollTask: Task<Void, Never>?

    enum AuthPhase: Equatable {
        case idle
        case fetchingToken
        case awaitingApproval
        case completing
    }

    func beginAuth() async {
        authPhase = .fetchingToken
        authError = nil
        do {
            let t = try await client.getToken()
            self.authToken = t
            let url = await client.authorizationURL(token: t)
            NSWorkspace.shared.open(url)
            self.authPhase = .awaitingApproval
            startAuthPolling(token: t)
        } catch {
            self.authError = error.localizedDescription
            self.authPhase = .idle
        }
    }

    private func startAuthPolling(token: String) {
        authPollTask?.cancel()
        authPollTask = Task { [weak self] in
            // Exponential backoff for transient errors; reset on each retry of
            // the "still pending" code 14 case.
            var backoff: Duration = .seconds(2)
            let deadline = Date().addingTimeInterval(300)
            while !Task.isCancelled, Date() < deadline {
                try? await Task.sleep(for: backoff)
                if Task.isCancelled { return }
                guard let self else { return }
                let outcome = await self.attemptCompleteAuth(token: token)
                switch outcome {
                case .success: return
                case .pending:
                    backoff = .seconds(2)  // reset; we're in healthy polling
                case .tokenDead(let msg):
                    await MainActor.run {
                        self.authPhase = .idle
                        self.authError = "Sign-in failed: \(msg). Try again."
                    }
                    return
                case .transient:
                    backoff = min(backoff * 2, .seconds(30))
                }
            }
            await MainActor.run {
                guard let self else { return }
                guard self.authPhase == .awaitingApproval else { return }
                self.authPhase = .idle
                self.authError = "Sign-in timed out. Please try again."
            }
        }
    }

    private enum AuthPollOutcome {
        case success
        case pending           // Last.fm code 14: still waiting for user
        case tokenDead(String) // codes 4/15/etc. give up, surface error
        case transient         // network blip. back off and retry
    }

    private func attemptCompleteAuth(token: String) async -> AuthPollOutcome {
        do {
            let (sk, name) = try await client.getSession(token: token)
            let issuingKey = await client.currentAPIKey
            try Keychain.set(sk, for: "sessionKey")
            try Keychain.set(name, for: "username")
            await MainActor.run {
                UserDefaults.standard.set(issuingKey, forKey: Self.sessionAPIKeyDefaultsKey)
                self.username = name
                self.isAuthenticated = true
                self.authToken = nil
                self.authError = nil
                self.authPhase = .idle
            }
            engine.requestFlushNow()
            return .success
        } catch LastFMError.api(let code, let msg) {
            switch code {
            case 14: return .pending
            case 4, 9, 15, 26: return .tokenDead(msg.isEmpty ? "token rejected (code \(code))" : msg)
            default: return .tokenDead("API error \(code)" + (msg.isEmpty ? "" : ": \(msg)"))
            }
        } catch {
            return .transient
        }
    }

    func cancelAuth() {
        authPollTask?.cancel()
        authPollTask = nil
        authToken = nil
        authError = nil
        authPhase = .idle
    }

    func signOut() {
        cancelAuth()
        invalidateSession()
        Log.lifecycle.info("signed out")
    }
}
