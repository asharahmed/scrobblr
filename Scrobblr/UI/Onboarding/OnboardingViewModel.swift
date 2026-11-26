import Foundation
import SwiftUI
import AppKit

/// Step machine for the first-launch onboarding window.
///
/// Each step has a "primary action" (Continue / Sign in / Grant) and a "skip"
/// path. Permissions are triggered only on explicit user action. never
/// implicitly. After the final step we set `@AppStorage("hasCompletedOnboarding")`
/// and the window closes; subsequent launches go straight to the menu bar.
@MainActor
final class OnboardingViewModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome
        case credentials  // per-user key, only when the build has no app key
        case lastFM       // Browser approval, exchange token for session
        case music        // AppleScript Automation TCC prompt
        case finish
    }

    @Published var step: Step = .welcome
    @Published var musicPermission: AutomationPermission.Status = .notDetermined
    @Published var musicProbeInFlight: Bool = false
    @Published var launchAtLogin: Bool = LoginItem.shared.isEnabled

    let coordinator: AppCoordinator

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self.musicPermission = AutomationPermission.status(forBundleID: "com.apple.Music")
    }

    var progress: Double {
        let steps = visibleSteps
        let index = steps.firstIndex(of: step) ?? 0
        return Double(index + 1) / Double(steps.count)
    }

    /// Steps this build actually shows. The credential step is skipped when
    /// Scrobblr ships its own Last.fm key, which is the normal case: users
    /// just approve the app in their browser.
    var visibleSteps: [Step] {
        Step.allCases.filter { $0 != .credentials || !Credentials.hasBuiltIn }
    }

    func advance() {
        move(by: 1)
    }

    func goBack() {
        move(by: -1)
    }

    private func move(by delta: Int) {
        let steps = visibleSteps
        guard let index = steps.firstIndex(of: step) else { return }
        let next = index + delta
        guard steps.indices.contains(next) else { return }
        step = steps[next]
    }

    // MARK: - Music permission

    /// Triggers the system TCC prompt by issuing a real AppleEvent. macOS
    /// shows its standard "Scrobblr would like to control Music" dialog the
    /// first time; subsequent calls return the cached decision.
    func requestMusicPermission() async {
        musicProbeInFlight = true
        defer { musicProbeInFlight = false }

        // Step 1: issue a real AppleScript event, which is what triggers the
        // TCC prompt (AEDeterminePermissionToAutomateTarget with
        // askUserIfNeeded=true is unreliable in practice).
        _ = await MusicAppBridge.shared.snapshot()

        // Step 2: poll TCC for the user's decision. The system prompt is
        // modal-ish but doesn't have a guaranteed deadline; up to 6 seconds
        // (12 checks at 500ms) should cover slow clickers.
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(500))
            let s = AutomationPermission.status(forBundleID: "com.apple.Music")
            if s == .granted || s == .denied {
                musicPermission = s
                break
            }
        }

        if musicPermission == .granted {
            coordinator.observer.enablePlaybackPolling()
        }
    }

    // MARK: - Finish

    /// Called when the user finishes (Done) or skips the entire flow.
    ///
    /// We always mark onboarding complete on Done. the user explicitly
    /// chose to dismiss the flow, so don't ambush them with it on every
    /// launch. They can revisit via the "Welcome…" item in the menu bar
    /// or Settings → General → Welcome.
    func finish() {
        if launchAtLogin != LoginItem.shared.isEnabled {
            _ = LoginItem.shared.setEnabled(launchAtLogin)
        }
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        coordinator.didFinishOnboarding()
    }
}
