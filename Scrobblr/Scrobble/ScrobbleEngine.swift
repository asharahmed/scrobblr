import Foundation
import Combine

/// Listens to PlaybackObserver and decides what to scrobble.
///
/// Correctness invariants this rewrite establishes:
///
///   * "Played" is *elapsed listening time*, accumulated on a monotonic
///     ContinuousClock — independent of the playhead position and immune to
///     wall-clock skew / NTP corrections. Advances only when state == .playing.
///   * Candidate identity is `(track.identity, startedAt)`, not just identity —
///     so replays of the same song don't fold together or double-scrobble.
///   * Submission acknowledges per-record per Last.fm's `ignoredMessage` codes;
///     accepted records are dropped, permanent rejections (codes 1/2/3) are
///     dropped with a log, transient (code 4 clock skew) sit and retry, daily
///     limit (code 5) pauses the loop until tomorrow.
///   * Permanent batch errors drop records by id-matching response items, never
///     "the head of the batch".
///   * The flush Task is owned; `stop()` cancels it cleanly for app shutdown.
@MainActor
final class ScrobbleEngine: ObservableObject {
    private let observer: PlaybackObserver
    private let client: LastFMClient
    private let queue: ScrobbleQueue
    private let monitor: SystemMonitor

    private var subs: Set<AnyCancellable> = []
    private var ticker: Timer?
    private var flushTask: Task<Void, Never>?

    /// Candidate currently being watched for "did it cross the threshold".
    /// Identified by (track.identity, startedAt).
    private struct Candidate {
        let track: Track
        let startedAt: Date              // wall-clock for the Last.fm timestamp
        let clockStart: ContinuousClock.Instant  // monotonic anchor
        var accumulatedElapsed: Duration // sealed elapsed at the last pause
        var lastResumeAt: ContinuousClock.Instant?  // nil if not currently playing
        var enqueued: Bool

        /// Compute total elapsed listening time as-of now, including any
        /// in-progress play segment.
        func elapsed(now: ContinuousClock.Instant) -> Duration {
            if let resume = lastResumeAt {
                return accumulatedElapsed + (now - resume)
            }
            return accumulatedElapsed
        }
    }
    private var candidate: Candidate?

    @Published private(set) var queueCount: Int = 0
    @Published private(set) var lastError: String?
    @Published private(set) var needsReauth: Bool = false
    @Published private(set) var isFlushing: Bool = false

    struct LastScrobble: Equatable, Hashable {
        let title: String
        let artist: String
        /// When the scrobble landed at Last.fm (for "just now" UI).
        let uploadedAt: Date
        /// When the track was played (for "Played 2h ago" detail).
        let playedAt: Date
    }
    @Published private(set) var lastScrobbled: LastScrobble?
    /// Ring buffer of the most-recent N scrobbles, newest first. Lives in
    /// memory only — for a durable history use Last.fm itself.
    @Published private(set) var recentScrobbles: [LastScrobble] = []
    private let recentLimit = 50

    /// Identity of the currently-playing track if we know it's loved on
    /// Last.fm. Populated optimistically by `loveCurrent()`; not pre-fetched
    /// (would need an extra round-trip per track change).
    @Published private(set) var lovedIdentity: String? = nil

    init(observer: PlaybackObserver, client: LastFMClient, queue: ScrobbleQueue, monitor: SystemMonitor) {
        self.observer = observer
        self.client = client
        self.queue = queue
        self.monitor = monitor
    }

    func start() {
        observer.trackStarted
            .sink { [weak self] track, when in
                Task { @MainActor in self?.onTrackStarted(track, at: when) }
            }
            .store(in: &subs)

        observer.trackEnded
            .sink { [weak self] track, when, _ in
                // We deliberately ignore the observer's `played` parameter:
                // it's playhead-based and unreliable. We compute elapsed from
                // our own ContinuousClock accumulator.
                Task { @MainActor in self?.onTrackEnded(track, startedAt: when) }
            }
            .store(in: &subs)

        // State changes feed the elapsed-time accumulator (pause = freeze).
        observer.$snapshot
            .sink { [weak self] snap in
                Task { @MainActor in self?.updateAccumulator(state: snap.state) }
            }
            .store(in: &subs)

        ticker = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluateCandidate() }
        }

        flushTask = Task { [weak self] in await self?.runFlushLoop() }
        Task { await refreshQueueCount() }
    }

    // MARK: - Love

    /// Heart the currently-playing track via `track.love`. Updates
    /// `lovedIdentity` optimistically — reverts on API error.
    func loveCurrent() {
        guard let track = observer.snapshot.track else { return }
        let identity = track.identity
        let artist = track.artist
        let title = track.title
        let prevLoved = lovedIdentity
        lovedIdentity = identity
        Task {
            do {
                try await client.love(artist: artist, track: title)
                Log.api.info("loved track")
            } catch {
                Log.api.error("love failed: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    if self.lovedIdentity == identity { self.lovedIdentity = prevLoved }
                    self.lastError = "Couldn't love: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Cancel inflight work for orderly shutdown.
    func stop() {
        flushTask?.cancel()
        flushTask = nil
        ticker?.invalidate()
        ticker = nil
        subs.removeAll()
    }

    // MARK: - Track lifecycle

    private func onTrackStarted(_ track: Track, at when: Date) {
        // Reset love state on every new track. We don't pre-fetch the
        // server-side loved state (it'd require a per-track round trip);
        // the heart is "loved this session" only.
        lovedIdentity = nil
        candidate = Candidate(
            track: track,
            startedAt: when,
            clockStart: .now,
            accumulatedElapsed: .zero,
            lastResumeAt: .now,
            enqueued: false
        )
        guard track.isScrobbleEligible else {
            Log.scrobble.info("track ineligible — \(track.title, privacy: .private) origin=\(track.origin.rawValue, privacy: .public)")
            return
        }
        Log.scrobble.info("now playing — \(track.title, privacy: .private)")
        Task { [client] in
            do { try await client.updateNowPlaying(track) }
            catch {
                Log.api.error("updateNowPlaying failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func onTrackEnded(_ track: Track, startedAt: Date) {
        defer { candidate = nil }
        guard var c = candidate,
              c.track.identity == track.identity,
              c.startedAt == startedAt,    // ← prevents replay double-scrobble
              !c.enqueued,
              c.track.isScrobbleEligible
        else { return }
        let played = c.elapsed(now: .now)
        if ScrobbleRules.qualifies(played: played, duration: c.track.durationSeconds) {
            enqueue(&c)
        }
    }

    private func evaluateCandidate() {
        guard var c = candidate, !c.enqueued, c.track.isScrobbleEligible else { return }
        let played = c.elapsed(now: .now)
        if ScrobbleRules.qualifies(played: played, duration: c.track.durationSeconds) {
            enqueue(&c)
            candidate = c
        }
    }

    /// Called on every snapshot to advance / freeze the elapsed-time
    /// accumulator. `.playing` resumes the clock; anything else seals it.
    private func updateAccumulator(state: PlayerState) {
        guard var c = candidate else { return }
        let now = ContinuousClock.now
        switch state {
        case .playing:
            if c.lastResumeAt == nil {
                c.lastResumeAt = now
            }
        case .paused, .stopped:
            if let resume = c.lastResumeAt {
                c.accumulatedElapsed = c.accumulatedElapsed + (now - resume)
                c.lastResumeAt = nil
            }
        }
        candidate = c
    }

    private func enqueue(_ c: inout Candidate) {
        let record = ScrobbleRecord(track: c.track, startedAt: c.startedAt)
        c.enqueued = true
        let title = c.track.title
        Log.scrobble.info("queued — \(title, privacy: .private)")
        Task { [queue] in
            await queue.enqueue(record)
            await MainActor.run { Task { await self.refreshQueueCount() } }
        }
    }

    private func refreshQueueCount() async {
        let n = await queue.count()
        await MainActor.run { self.queueCount = n }
    }

    // MARK: - Flush loop

    private func runFlushLoop() async {
        var backoff: Duration = .seconds(10)
        var pauseUntil: Date? = nil
        while !Task.isCancelled {
            // Honour daily-limit pause set by previous iteration.
            if let until = pauseUntil, Date() < until {
                let remaining = until.timeIntervalSinceNow
                try? await Task.sleep(for: .seconds(min(remaining, 3600)))
                continue
            }
            pauseUntil = nil

            let online = await monitor.isOnline
            let asleep = await monitor.isAsleep
            if !online || asleep {
                Log.scrobble.info("flush paused: online=\(online, privacy: .public) asleep=\(asleep, privacy: .public)")
                await monitor.waitForResume()
                backoff = .seconds(10)
                continue
            }

            let batch = await queue.nextBatch(limit: 50)
            if batch.isEmpty {
                try? await Task.sleep(for: .seconds(30))
                backoff = .seconds(10)
                continue
            }

            await MainActor.run { self.isFlushing = true }
            do {
                let results = try await client.scrobble(batch)
                pauseUntil = try await applyResults(results, batch: batch)
                await refreshQueueCount()
                let acceptedIDs = Set(results.filter { $0.acceptance.isAccepted }.map(\.id))
                let acceptedRecords = batch.filter { acceptedIDs.contains($0.id) }
                if let last = acceptedRecords.last {
                    await MainActor.run {
                        self.lastError = nil
                        self.needsReauth = false
                        self.isFlushing = false
                        let now = Date()
                        let entries = acceptedRecords.map {
                            LastScrobble(
                                title: $0.track, artist: $0.artist,
                                uploadedAt: now,
                                playedAt: Date(timeIntervalSince1970: TimeInterval($0.timestamp))
                            )
                        }
                        self.lastScrobbled = entries.last
                        // Prepend newest, cap at recentLimit.
                        self.recentScrobbles = Array((entries.reversed() + self.recentScrobbles).prefix(self.recentLimit))
                        _ = last
                    }
                } else {
                    await MainActor.run { self.isFlushing = false }
                }
                backoff = .seconds(10)
            } catch let e as LastFMError {
                Log.api.error("scrobble api error: \(String(describing: e), privacy: .public)")
                await MainActor.run {
                    self.lastError = "Scrobble error: \(e)"
                    self.isFlushing = false
                }
                if e.requiresReauth {
                    await MainActor.run { self.needsReauth = true }
                    // Pause flush until user re-auths; check back in 5 min.
                    try? await Task.sleep(for: .seconds(300))
                } else if e.isTransient {
                    await queue.markAttempted(ids: batch.map(\.id))
                    try? await Task.sleep(for: backoff)
                    backoff = min(backoff * 2, .seconds(3600))
                } else {
                    // Permanent batch-level failure with no per-record detail —
                    // bump attempts; drop records that have exceeded 5 attempts.
                    await queue.markAttempted(ids: batch.map(\.id))
                    let toDrop = await queue.idsExceedingAttempts(5)
                    for id in toDrop { await queue.drop(id: id) }
                    await refreshQueueCount()
                }
            } catch {
                Log.api.error("scrobble error: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    self.lastError = "Scrobble error: \(error.localizedDescription)"
                    self.isFlushing = false
                }
                await queue.markAttempted(ids: batch.map(\.id))
                try? await Task.sleep(for: backoff)
                backoff = min(backoff * 2, .seconds(3600))
            }
        }
    }

    /// Apply per-record acceptance to the queue. Returns a date until which
    /// the flush loop should pause (for daily-limit responses).
    private func applyResults(_ results: [ScrobbleResult], batch: [ScrobbleRecord]) async throws -> Date? {
        var pauseUntil: Date? = nil
        var toAcknowledge: [UUID] = []
        var toDrop: [UUID] = []
        var toRetry: [UUID] = []
        for r in results {
            switch r.acceptance.disposition {
            case .acknowledge:
                toAcknowledge.append(r.id)
            case .drop:
                toDrop.append(r.id)
                if case .ignored(let code, let msg) = r.acceptance {
                    Log.api.error("scrobble dropped code=\(code, privacy: .public) msg=\(msg, privacy: .public)")
                }
            case .retryLater:
                toRetry.append(r.id)
            case .pauseDay:
                // Daily limit hit. Pause until midnight UTC (Last.fm resets daily).
                let cal = Calendar(identifier: .gregorian)
                var comps = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: Date())
                comps.hour = 0; comps.minute = 0; comps.second = 0
                if let next = cal.date(byAdding: .day, value: 1, to: cal.date(from: comps) ?? Date()) {
                    pauseUntil = next
                }
                toRetry.append(r.id)
            }
        }
        if !toAcknowledge.isEmpty {
            await queue.acknowledge(ids: toAcknowledge)
            Log.api.info("scrobbled \(toAcknowledge.count, privacy: .public) records")
        }
        for id in toDrop { await queue.drop(id: id) }
        if !toRetry.isEmpty {
            await queue.markAttempted(ids: toRetry)
        }
        return pauseUntil
    }
}
