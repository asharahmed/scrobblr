import Foundation
import Combine
import AppKit

/// Owns playback state. Composes the two detection sources:
///   - DistributedNotificationSource (event-driven, drives transitions)
///   - MusicAppBridge (1 Hz position poll while playing, plus fallback for
///     Tahoe's `current track` regression when notifications drop metadata)
///
/// Publishes a single PlaybackSnapshot so the rest of the app reads from one
/// place. Marked @MainActor because we drive a SwiftUI menu bar UI from it.
@MainActor
final class PlaybackObserver: ObservableObject {
    @Published private(set) var snapshot = PlaybackSnapshot(
        state: .stopped, track: nil, position: nil, startedAt: nil
    )

    /// Artwork for the currently playing track. Updated asynchronously after
    /// the track changes; nil until the AppleScript fetch resolves.
    @Published private(set) var artwork: NSImage?

    private var notifSource: DistributedNotificationSource?
    private var pollTimer: Timer?     // 1 Hz: ground truth from Music.app
    private var tickTimer: Timer?     // 4 Hz: local interpolation for smooth UI
    private var lastPollAt: Date?     // when the last 1 Hz poll completed
    private var lastPolledPosition: Double?  // position reported by that poll
    private var artworkTask: Task<Void, Never>?

    /// Emits when we detect a track has been *meaningfully* started. i.e. a
    /// new identity that the engine should consider for scrobbling. Replays of
    /// the same identity (e.g. user seeks back to the start) also emit; the
    /// engine handles dedupe.
    let trackStarted = PassthroughSubject<(Track, Date), Never>()

    /// Emits when a track that previously emitted `trackStarted` has finished
    /// its play. The third tuple element is the *playhead position* at the
    /// moment of end. kept for compatibility but unreliable for elapsed-time
    /// math (playhead can jump on seek). The engine computes its own elapsed
    /// time from a monotonic clock.
    let trackEnded = PassthroughSubject<(Track, Date, Double), Never>()

    private var currentIdentity: String?

    /// True once the user has granted (or we've verified) AppleScript access
    /// to Music.app. Until then we run notification-only. distributed
    /// notifications need no TCC permission. The bridge is the path that
    /// triggers the permission prompt, so we don't touch it until invited to.
    private(set) var playbackPollingEnabled: Bool = false

    func start() {
        let source = DistributedNotificationSource { [weak self] state, track in
            Task { @MainActor in await self?.apply(state: state, track: track, from: .notification) }
        }
        source.start()
        notifSource = source
    }

    /// Called once the user grants AppleScript permission in onboarding (or
    /// when we detect it was already granted on relaunch). Primes the
    /// bridge-based snapshot and turns on the 1 Hz position poll.
    func enablePlaybackPolling() {
        guard !playbackPollingEnabled else { return }
        playbackPollingEnabled = true
        Task { @MainActor in
            if let snap = await MusicAppBridge.shared.snapshot() {
                await apply(state: snap.state, track: snap.track, from: .poll(position: snap.position))
            }
        }
    }

    /// Stop all timers and observers. Call before the app quits or when
    /// rebuilding the observer in tests. We rely on this rather than a deinit
    /// because Timer is not Sendable so a nonisolated deinit can't touch it
    /// under Swift 6 strict concurrency.
    func stop() {
        notifSource?.stop()
        notifSource = nil
        stopPolling()
        artworkTask?.cancel()
        artworkTask = nil
    }

    private enum Origin {
        case notification
        case poll(position: Double)
    }

    private func apply(state: PlayerState, track: Track?, from origin: Origin) async {
        let now = Date()
        let prevTrack = snapshot.track
        let prevIdentity = currentIdentity

        // Notification path can omit fields on Tahoe. backfill from the bridge.
        // Only consult the bridge if the user has granted AppleScript permission.
        // Important: if Music advanced *between* the notification and our bridge
        // call, the bridge will report a *different* track. We must not blindly
        // substitute, or we'd skip the old track's trackEnded and never scrobble
        // it. So we only accept a bridge-track when we have no notification
        // track at all (otherwise we trust the notification).
        var resolvedTrack = track
        if playbackPollingEnabled, state == .playing, resolvedTrack == nil {
            if let bridged = await MusicAppBridge.shared.snapshot()?.track {
                resolvedTrack = bridged
            }
        }
        // If the notification *did* give us a track but it lacks duration,
        // try to fill in from the bridge (durations are essential for the
        // ≥50% scrobble rule).
        if playbackPollingEnabled, state == .playing, let rt = resolvedTrack, rt.durationSeconds == nil {
            if let bridged = await MusicAppBridge.shared.snapshot()?.track,
               bridged.identity == rt.identity, let dur = bridged.durationSeconds {
                resolvedTrack = Track(
                    title: rt.title, artist: rt.artist, album: rt.album,
                    albumArtist: rt.albumArtist, trackNumber: rt.trackNumber,
                    durationSeconds: dur, persistentID: rt.persistentID,
                    storeAdamID: rt.storeAdamID, origin: rt.origin
                )
            }
        }

        let newIdentity = resolvedTrack?.identity

        // Track change: end old, start new.
        if newIdentity != prevIdentity {
            if let old = prevTrack, let started = snapshot.startedAt {
                let played = (snapshot.position ?? 0)
                trackEnded.send((old, started, played))
            }
            if let new = resolvedTrack, state == .playing {
                snapshot = PlaybackSnapshot(state: .playing, track: new, position: 0, startedAt: now)
                currentIdentity = new.identity
                artwork = nil
                let identity = new.identity
                let artist = new.artist
                let title = new.title
                // Cancel any prior in-flight artwork fetch; rapid track-skips
                // shouldn't fire N concurrent iTunes lookups.
                artworkTask?.cancel()
                artworkTask = Task { [weak self] in
                    let data = await ArtworkFetcher.shared.fetch(
                        identity: identity, artist: artist, title: title
                    )
                    await MainActor.run {
                        guard let self, self.currentIdentity == identity else { return }
                        self.artwork = data.flatMap { NSImage(data: $0) }
                    }
                }
                trackStarted.send((new, now))
            } else {
                // Preserve a polled playhead position if available. Cold launch
                // with Music paused mid-track lands here; without this the UI
                // shows 0:00 even though the user paused at 1:47.
                var initialPosition: Double? = nil
                if case let .poll(p) = origin { initialPosition = p }
                snapshot = PlaybackSnapshot(
                    state: state, track: resolvedTrack,
                    position: initialPosition, startedAt: nil
                )
                currentIdentity = newIdentity
            }
        } else {
            // Same track. just update state/position.
            var pos = snapshot.position
            if case let .poll(p) = origin { pos = p }
            snapshot = PlaybackSnapshot(
                state: state,
                track: resolvedTrack ?? snapshot.track,
                position: pos,
                startedAt: snapshot.startedAt
            )
        }

        // Position polling: only run when playing AND we have permission.
        if state == .playing && playbackPollingEnabled {
            startPolling()
        } else {
            stopPolling()
        }
    }

    private func startPolling() {
        if pollTimer == nil {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    guard let snap = await MusicAppBridge.shared.snapshot() else { return }
                    self.lastPollAt = Date()
                    self.lastPolledPosition = snap.position
                    await self.apply(state: snap.state, track: snap.track, from: .poll(position: snap.position))
                }
            }
        }
        if tickTimer == nil {
            // Interpolates position between polls so the UI progress bar
            // advances smoothly rather than stepping once per second.
            tickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.interpolatePosition() }
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate(); pollTimer = nil
        tickTimer?.invalidate(); tickTimer = nil
        lastPollAt = nil
        lastPolledPosition = nil
    }

    private func interpolatePosition() {
        guard snapshot.state == .playing,
              let base = lastPolledPosition,
              let at = lastPollAt else { return }
        // Always interpolate from the poll-time anchor, never from the
        // already-interpolated value (otherwise drift compounds).
        let interpolated = base + min(Date().timeIntervalSince(at), 1.0)
        snapshot = PlaybackSnapshot(
            state: snapshot.state,
            track: snapshot.track,
            position: interpolated,
            startedAt: snapshot.startedAt
        )
    }
}
