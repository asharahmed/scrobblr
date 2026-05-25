import Foundation
import AppKit

/// Talks to Music.app via NSAppleScript. An actor (not the old @unchecked
/// Sendable + serial DispatchQueue) so the main thread never blocks on
/// `executeAndReturnError`; the bridge runs on its own cooperative pool.
///
/// macOS 26 (Tahoe) regression note (FB19908171): `set t to current track`
/// throws `-1728` for non-library tracks. We avoid that by reading every
/// field via direct property access (`name of current track`) — see source.
///
/// Field separator: `\u{001F}` (ASCII Unit Separator), which can't appear in
/// Music metadata, so we don't have to defend against tab-in-title attacks.
actor MusicAppBridge {
    static let shared = MusicAppBridge()

    private var compiledScript: NSAppleScript?

    private static let sep = "\u{001F}"  // 10-field separator; never appears in metadata

    private let source = """
    tell application "Music"
        if it is running then
            try
                set s to player state as text
            on error
                set s to "stopped"
            end try
            try
                set p to player position as text
            on error
                set p to "0"
            end try
            try
                set tName to (name of current track) as text
            on error
                set tName to ""
            end try
            try
                set tArtist to (artist of current track) as text
            on error
                set tArtist to ""
            end try
            try
                set tAlbum to (album of current track) as text
            on error
                set tAlbum to ""
            end try
            try
                set tAlbumArtist to (album artist of current track) as text
            on error
                set tAlbumArtist to ""
            end try
            try
                set tDur to (duration of current track) as text
            on error
                set tDur to "0"
            end try
            try
                set tNum to (track number of current track) as text
            on error
                set tNum to "0"
            end try
            try
                set tPid to (persistent ID of current track) as text
            on error
                set tPid to ""
            end try
            try
                set tKind to (kind of current track) as text
            on error
                set tKind to ""
            end try
            set sep to (ASCII character 31)
            return s & sep & p & sep & tName & sep & tArtist & sep & tAlbum & sep & tAlbumArtist & sep & tDur & sep & tNum & sep & tPid & sep & tKind
        else
            set sep to (ASCII character 31)
            return "stopped" & sep & "0" & sep & "" & sep & "" & sep & "" & sep & "" & sep & "0" & sep & "0" & sep & "" & sep & ""
        end if
    end tell
    """

    struct Snapshot: Sendable {
        var state: PlayerState
        var position: Double
        var track: Track?
    }

    func snapshot() -> Snapshot? {
        if compiledScript == nil {
            let s = NSAppleScript(source: source)
            var err: NSDictionary?
            _ = s?.compileAndReturnError(&err)
            if err != nil {
                Log.playback.error("MusicAppBridge: compile failed")
                return nil
            }
            compiledScript = s
        }
        guard let script = compiledScript else { return nil }
        var err: NSDictionary?
        let result = script.executeAndReturnError(&err)
        if err != nil { return nil }
        guard let line = result.stringValue else { return nil }
        return parse(line)
    }

    private func parse(_ line: String) -> Snapshot? {
        let parts = line.components(separatedBy: Self.sep)
        guard parts.count == 10 else { return nil }
        let state: PlayerState = switch parts[0].lowercased() {
        case "playing": .playing
        // AppleScript surfaces "paused" and "stopped"; unknown future states
        // default to paused (not stopped) so we don't blow away current track.
        case "stopped": .stopped
        default:        .paused
        }
        let position = Double(parts[1]) ?? 0
        let name = parts[2]
        let artist = parts[3]
        if name.isEmpty {
            return Snapshot(state: state, position: position, track: nil)
        }
        let album = parts[4].isEmpty ? nil : parts[4]
        let albumArtist = parts[5].isEmpty ? nil : parts[5]
        let dur = Double(parts[6]) ?? 0
        let trackNum = Int(parts[7]) ?? 0
        let pid = parts[8].isEmpty ? nil : parts[8]
        let kind = parts[9]

        let origin: Track.Origin = switch kind {
        case let k where k.contains("Music file"): .localFile
        case let k where k.contains("Apple Music"): .appleMusicCatalog
        case let k where k.contains("URL"): .stream
        default: .unknown
        }

        let track = Track(
            title: name,
            artist: artist,
            album: album,
            albumArtist: albumArtist,
            trackNumber: trackNum > 0 ? trackNum : nil,
            durationSeconds: dur > 0 ? dur : nil,
            persistentID: pid,
            storeAdamID: nil,
            origin: origin
        )
        return Snapshot(state: state, position: position, track: track)
    }
}

/// Lightweight Music.app-running probe. NSWorkspace.runningApplications is
/// MainActor-isolated, so this lives outside the bridge actor.
@MainActor
enum MusicAppPresence {
    static var isMusicRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.Music"
        }
    }
}
