import Foundation
import AppKit
import ApplicationServices

/// Probes (and, on request, triggers) the macOS TCC permission for sending
/// Apple Events to a target app. Uses the Core Apple Event API directly so we
/// can distinguish "denied", "not yet asked", and "target not running" without
/// firing a script.
///
/// `noErr` (0)              → granted
/// `errAEEventNotPermitted` (-1743) → denied (or never asked, if askUserIfNeeded was false)
/// `procNotFound` (-600)    → target app not running; can't determine yet
enum AutomationPermission {
    enum Status {
        case granted
        case denied
        case notDetermined
        case targetNotRunning
    }

    static func status(forBundleID bundleID: String, askUserIfNeeded: Bool = false) -> Status {
        // Build an AEAddressDesc referencing the target app by bundle id.
        guard let cfBundle = bundleID as CFString? else { return .notDetermined }
        let bundleData = (cfBundle as String).data(using: .utf8) ?? Data()
        var address = AEAddressDesc()
        defer { AEDisposeDesc(&address) }
        let createErr: OSErr = bundleData.withUnsafeBytes { raw in
            AECreateDesc(
                typeApplicationBundleID,
                raw.baseAddress, raw.count,
                &address
            )
        }
        guard createErr == noErr else { return .notDetermined }

        // Probe with a representative event (kAEGetData / 'getd'. read-only).
        let result = AEDeterminePermissionToAutomateTarget(
            &address, typeWildCard, typeWildCard, askUserIfNeeded
        )
        switch result {
        case noErr: return .granted
        case OSStatus(procNotFound): return .targetNotRunning
        case OSStatus(errAEEventNotPermitted): return .denied
        case -1744:  // errAEEventWouldRequireUserConsent
            return .notDetermined
        default:
            return .notDetermined
        }
    }

    /// Opens System Settings → Privacy & Security → Automation. Use when the
    /// user has denied and needs to re-enable.
    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
