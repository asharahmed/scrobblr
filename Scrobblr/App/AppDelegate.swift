import AppKit

/// Wired via `@NSApplicationDelegateAdaptor` on the App scene.
///
/// We override two things:
///
///   * `applicationShouldTerminateAfterLastWindowClosed → false` — Scrobblr
///     is a menu-bar resident. Closing the welcome window with the red X
///     must NOT quit the whole agent, or users will think the app crashed.
///   * Translocation detection — Gatekeeper randomly relocates first-run
///     downloads into a read-only mount under `/private/var/folders/.../
///     AppTranslocation/`. Login items registered from there break on
///     reboot. If we detect it, we present a blocking dialog steering the
///     user to move Scrobblr to /Applications.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        checkForTranslocation()
    }

    private func checkForTranslocation() {
        let path = Bundle.main.bundlePath
        guard path.contains("/AppTranslocation/") else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Move Scrobblr to your Applications folder"
        alert.informativeText = """
            macOS is running this copy of Scrobblr from a read-only quarantine \
            mount. Some features — including Launch at login and software updates \
            — will not work correctly from here.

            Please move Scrobblr.app to your Applications folder and reopen it.
            """
        alert.addButton(withTitle: "Quit and Move Manually")
        alert.addButton(withTitle: "Continue Anyway")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            NSApp.terminate(nil)
        }
    }
}
