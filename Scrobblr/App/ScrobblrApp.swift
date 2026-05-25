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

    // Forward nested ObservableObject changes (observer.snapshot, engine.*)
    // up so SwiftUI views that observe `coordinator` re-render. Without this,
    // updates inside observer/engine don't propagate because @StateObject only
    // subscribes to coordinator's own objectWillChange.
    private var forwarders: Set<AnyCancellable> = []

    init() {
        let sk = Keychain.get("sessionKey")
        // Use placeholder credentials if user hasn't configured BYOK yet.
        // the client will still construct, but auth/scrobble methods will
        // surface API errors that the onboarding flow catches and routes
        // back to the BYOK step. Real values are injected once Credentials
        // is configured.
        let creds = Credentials.shared
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

        monitor.start()
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
    }

    /// Store user-provided Last.fm BYOK credentials, push them into the
    /// running client, and clear any stale session key (since it was issued
    /// against a different application).
    func setCredentials(apiKey: String, sharedSecret: String) throws {
        try credentials.store(apiKey: apiKey, sharedSecret: sharedSecret)
        let key = apiKey
        let secret = sharedSecret
        Task { await client.updateCredentials(apiKey: key, sharedSecret: secret) }
        // Existing session key was issued against a different (or empty) key.
        // wipe so the user re-authenticates.
        Keychain.delete("sessionKey")
        Keychain.delete("username")
        Task { await client.setSessionKey(nil) }
        self.username = nil
        self.isAuthenticated = false
        Log.lifecycle.info("BYOK credentials updated")
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

    var menuBarSymbol: String {
        if !isAuthenticated { return "waveform.slash" }
        if engine.needsReauth { return "exclamationmark.triangle" }
        if UserScrobbleSettings.shared.isPaused { return "waveform.badge.minus" }
        switch observer.snapshot.state {
        case .playing:
            return observer.snapshot.track?.origin == .stream ? "antenna.radiowaves.left.and.right" : "waveform"
        case .paused: return "pause.circle"
        case .stopped: return "waveform.circle"
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
            try Keychain.set(sk, for: "sessionKey")
            try Keychain.set(name, for: "username")
            await MainActor.run {
                self.username = name
                self.isAuthenticated = true
                self.authToken = nil
                self.authError = nil
                self.authPhase = .idle
            }
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
        Keychain.delete("sessionKey")
        Keychain.delete("username")
        self.username = nil
        self.isAuthenticated = false
        Task { await client.setSessionKey(nil) }
    }
}
