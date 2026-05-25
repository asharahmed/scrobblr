import Foundation
import UserNotifications

/// Lightweight wrapper around UNUserNotificationCenter for the optional
/// "Now Playing" banner that appears on each track change.
///
/// The user opts in via Settings; nothing fires until they do. The first
/// opt-in triggers macOS's standard notification permission prompt.
@MainActor
enum NowPlayingNotifier {
    private static let center = UNUserNotificationCenter.current()

    /// Returns true if the user has granted notification permission and
    /// macOS will actually deliver our notifications.
    static func currentAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    /// Triggers macOS's permission prompt the first time. Returns the
    /// resulting authorization. No-op if already decided.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Log.lifecycle.error("notification auth failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Post a now-playing banner for the given track. Quietly drops if the
    /// user hasn't granted permission. Identifiers per-track so rapid
    /// changes coalesce in Notification Center.
    static func showNowPlaying(track: Track) async {
        guard await currentAuthorization() else { return }
        let content = UNMutableNotificationContent()
        content.title = track.title
        content.subtitle = track.artist
        if let album = track.album, !album.isEmpty {
            content.body = album
        }
        content.sound = nil
        content.threadIdentifier = "now-playing"

        let request = UNNotificationRequest(
            identifier: "now-playing-\(track.identity)",
            content: content,
            trigger: nil
        )
        // Cancel any previous now-playing banner so we don't stack them.
        center.removeDeliveredNotifications(withIdentifiers: ["now-playing"])
        try? await center.add(request)
    }
}
