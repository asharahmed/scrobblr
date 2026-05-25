import Foundation
import Combine

/// User-tunable scrobble parameters.
///
///   * `thresholdPercent`. minimum % of duration played, default 0.5 (50%)
///   * `thresholdSeconds`. absolute cap, default 240s (4 min)
///   * `skipDebounce`. minimum play time, default 5s
///   * `pauseUntil`. nil = active, otherwise scrobbling is suspended until
///     this date (or indefinitely if `.distantFuture`)
///   * `skipPodcasts`, `skipAudiobooks`, `skipMusicVideos`. content type filter
///
/// Persisted to UserDefaults. Defaults match Last.fm's published rules so
/// behaviour is unchanged unless the user touches a knob.
@MainActor
final class UserScrobbleSettings: ObservableObject {
    static let shared = UserScrobbleSettings()

    @Published var thresholdPercent: Double {
        didSet { UserDefaults.standard.set(thresholdPercent, forKey: "thresholdPercent") }
    }
    @Published var thresholdSeconds: Double {
        didSet { UserDefaults.standard.set(thresholdSeconds, forKey: "thresholdSeconds") }
    }
    @Published var skipPodcasts: Bool {
        didSet { UserDefaults.standard.set(skipPodcasts, forKey: "skipPodcasts") }
    }
    @Published var skipAudiobooks: Bool {
        didSet { UserDefaults.standard.set(skipAudiobooks, forKey: "skipAudiobooks") }
    }
    @Published var skipMusicVideos: Bool {
        didSet { UserDefaults.standard.set(skipMusicVideos, forKey: "skipMusicVideos") }
    }
    @Published var showNowPlayingNotifications: Bool {
        didSet { UserDefaults.standard.set(showNowPlayingNotifications, forKey: "showNowPlayingNotifications") }
    }
    @Published var pauseUntil: Date? {
        didSet {
            if let d = pauseUntil {
                UserDefaults.standard.set(d.timeIntervalSince1970, forKey: "pauseUntil")
            } else {
                UserDefaults.standard.removeObject(forKey: "pauseUntil")
            }
        }
    }

    var isPaused: Bool {
        guard let until = pauseUntil else { return false }
        return until > Date()
    }

    init() {
        let d = UserDefaults.standard
        self.thresholdPercent = (d.object(forKey: "thresholdPercent") as? Double) ?? 0.5
        self.thresholdSeconds = (d.object(forKey: "thresholdSeconds") as? Double) ?? 240
        self.skipPodcasts = (d.object(forKey: "skipPodcasts") as? Bool) ?? true
        self.skipAudiobooks = (d.object(forKey: "skipAudiobooks") as? Bool) ?? true
        self.skipMusicVideos = (d.object(forKey: "skipMusicVideos") as? Bool) ?? false
        self.showNowPlayingNotifications = (d.object(forKey: "showNowPlayingNotifications") as? Bool) ?? false
        if let ts = d.object(forKey: "pauseUntil") as? Double {
            let date = Date(timeIntervalSince1970: ts)
            self.pauseUntil = (date > Date()) ? date : nil
        } else {
            self.pauseUntil = nil
        }
    }

    // MARK: - Pause shortcuts

    func pauseFor(_ duration: TimeInterval) {
        pauseUntil = Date().addingTimeInterval(duration)
    }

    func pauseIndefinitely() {
        pauseUntil = Date.distantFuture
    }

    func resume() {
        pauseUntil = nil
    }
}
