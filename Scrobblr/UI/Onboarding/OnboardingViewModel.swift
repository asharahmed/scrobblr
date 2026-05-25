import Foundation
import SwiftUI
import AppKit

/// Step machine for the first-launch onboarding window.
///
/// Each step has a "primary action" (Continue / Sign in / Grant) and a "skip"
/// path. Permissions are triggered only on explicit user action — never
/// implicitly. After the final step we set `@AppStorage("hasCompletedOnboarding")`
/// and the window closes; subsequent launches go straight to the menu bar.
@MainActor
final class OnboardingViewModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome
        case credentials  // BYOK: API key + shared secret
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
        Double(step.rawValue + 1) / Double(Step.allCases.count)
    }

    func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func goBack() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        step = prev
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
    /// We always mark onboarding complete on Done — the user explicitly
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
