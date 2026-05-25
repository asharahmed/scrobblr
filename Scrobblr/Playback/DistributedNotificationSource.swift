import Foundation

/// Listens to `com.apple.Music.playerInfo` (and the legacy
/// `com.apple.iTunes.playerInfo` for back-compat — Music.app still posts both
/// on Sonoma/Sequoia/Tahoe). This is the primary signal: it's unaffected by
/// the macOS 15.4 MediaRemote clampdown because Music.app posts it directly,
/// not via mediaremoted.
///
/// userInfo keys we use:
///   Player State        "Playing" | "Paused" | "Stopped"
///   Name, Artist, Album, Album Artist
///   Total Time          milliseconds (Int)
///   Track Number        Int
///   PersistentID        Int (not the hex AppleScript returns — different field)
///   Store URL           "itmss://…?i=ADAMID" for catalog tracks
///   Location            "file://…" only for local files
///   Stream Title / Stream URL — present for radio; we skip scrobbling
// @unchecked Sendable: token state is only mutated from the main queue
// (we register/unregister observers on .main), and the handler is itself
// @Sendable. This conformance lets the .main observer closures capture self
// without strict-concurrency complaints.
final class DistributedNotificationSource: @unchecked Sendable {
    private let center = DistributedNotificationCenter.default()
    private var token1: NSObjectProtocol?
    private var token2: NSObjectProtocol?

    private let handler: @Sendable (PlayerState, Track?) -> Void

    init(handler: @escaping @Sendable (PlayerState, Track?) -> Void) {
        self.handler = handler
    }

    func start() {
        let names = [
            Notification.Name("com.apple.Music.playerInfo"),
            Notification.Name("com.apple.iTunes.playerInfo"),
        ]
        token1 = center.addObserver(forName: names[0], object: nil, queue: .main) { [weak self] n in
            self?.process(n.userInfo)
        }
        token2 = center.addObserver(forName: names[1], object: nil, queue: .main) { [weak self] n in
            self?.process(n.userInfo)
        }
    }

    func stop() {
        if let t = token1 { center.removeObserver(t) }
        if let t = token2 { center.removeObserver(t) }
        token1 = nil
        token2 = nil
    }

    private func process(_ ui: [AnyHashable: Any]?) {
        guard let ui else { return }
        let stateString = (ui["Player State"] as? String ?? "Stopped").lowercased()
        let state: PlayerState = switch stateString {
        case "playing": .playing
        case "paused": .paused
        default: .stopped
        }
        let title = ui["Name"] as? String ?? ""
        let artist = ui["Artist"] as? String ?? ""

        // Stop / fully-empty notification → clear track. But: classical,
        // audiobook, and soundtrack tracks sometimes ship with empty artist.
        // We pass those through and let `Track.isScrobbleEligible` decide
        // whether they're scrobble-worthy (that gate requires non-empty
        // artist + title); the UI still shows them.
        guard state != .stopped, !title.isEmpty else {
            handler(state, nil)
            return
        }

        let album = ui["Album"] as? String
        let albumArtist = ui["Album Artist"] as? String
        let trackNumber = ui["Track Number"] as? Int
        let totalMs = ui["Total Time"] as? Int
        let duration: Double? = totalMs.map { Double($0) / 1000.0 }

        // Track origin: presence of Stream URL/Title means radio (don't scrobble).
        // Presence of file:// Location means local. Otherwise — if there's a Store
        // URL with an i= adam id — it's an Apple Music catalog track.
        let location = ui["Location"] as? String
        let streamTitle = ui["Stream Title"] as? String
        let streamURL = ui["Stream URL"] as? String
        let storeURL = ui["Store URL"] as? String

        let origin: Track.Origin
        if (streamTitle?.isEmpty == false) || (streamURL?.isEmpty == false) {
            origin = .stream
        } else if let loc = location, loc.hasPrefix("file://") {
            origin = .localFile
        } else if storeURL != nil {
            origin = .appleMusicCatalog
        } else {
            origin = .unknown
        }

        // Pull the adam id (`i=<digits>`) from the Store URL, if present.
        let adamID: String? = {
            guard let s = storeURL, let comps = URLComponents(string: s) else { return nil }
            return comps.queryItems?.first(where: { $0.name == "i" })?.value
        }()

        // PersistentID arrives as an Int here. Render as hex (uppercase, 16 chars)
        // so it lines up with the AppleScript-returned form.
        let persistentID: String? = {
            if let n = ui["PersistentID"] as? Int64 {
                return String(format: "%016llX", n)
            }
            if let n = ui["PersistentID"] as? Int {
                return String(format: "%016llX", Int64(n))
            }
            return nil
        }()

        let track = Track(
            title: title,
            artist: artist,
            album: album,
            albumArtist: albumArtist,
            trackNumber: trackNumber,
            durationSeconds: duration,
            persistentID: persistentID,
            storeAdamID: adamID,
            origin: origin
        )
        handler(state, track)
    }
}
