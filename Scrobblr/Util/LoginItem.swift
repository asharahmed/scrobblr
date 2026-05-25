import Foundation
import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp`. the modern (macOS 13+) way
/// to register an app as a login item. No helper bundle needed: the main app
/// itself is the login item.
@MainActor
final class LoginItem: ObservableObject {
    static let shared = LoginItem()
    private let service = SMAppService.mainApp

    @Published private(set) var isEnabled: Bool

    init() {
        self.isEnabled = service.status == .enabled
    }

    /// Returns true on success, false if the system blocked the change (e.g.
    /// user must approve in System Settings).
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                    return false
                }
                try service.register()
            } else {
                try service.unregister()
            }
            isEnabled = (service.status == .enabled)
            Log.lifecycle.info("login item set to \(enabled, privacy: .public)")
            return true
        } catch {
            Log.lifecycle.error("login item toggle failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
