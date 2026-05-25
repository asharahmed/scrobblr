import Foundation

/// JSON-on-disk queue of pending scrobbles. v1 uses Codable + atomic file
/// writes; volume is low (Last.fm's per-user cap is ~2800/day, and even very
/// active listeners do <200) so SQLite would be over-engineered.
///
/// File lives in Application Support; the directory is created on first use.
actor ScrobbleQueue {
    private let url: URL
    private var records: [ScrobbleRecord] = []

    init(filename: String = "scrobble-queue.json") {
        let fm = FileManager.default
        // Fall back to a tmpdir path if Application Support is unreachable.
        // we'd rather lose persistence across launches than crash. Logging
        // makes the degraded state visible in Console.app.
        let base: URL = {
            do {
                let appSup = try fm.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask, appropriateFor: nil, create: true
                )
                let dir = appSup.appendingPathComponent("Scrobblr", isDirectory: true)
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                return dir
            } catch {
                Log.scrobble.error("ApplicationSupport unavailable, using tmpdir: \(error.localizedDescription, privacy: .public)")
                let dir = fm.temporaryDirectory.appendingPathComponent("Scrobblr", isDirectory: true)
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
                return dir
            }
        }()
        let path = base.appendingPathComponent(filename)
        self.url = path
        if let data = try? Data(contentsOf: path) {
            do {
                let loaded = try JSONDecoder().decode([ScrobbleRecord].self, from: data)
                self.records = loaded
                Log.scrobble.info("loaded queue with \(loaded.count, privacy: .public) records")
            } catch {
                // Corrupt file. rename it aside rather than silently zeroing.
                let ts = Int(Date().timeIntervalSince1970)
                let bad = path.appendingPathExtension("bad-\(ts)")
                try? fm.moveItem(at: path, to: bad)
                Log.scrobble.error("queue file corrupt, moved to \(bad.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func persist() {
        let snapshotCount = records.count
        guard let data = try? JSONEncoder().encode(records) else {
            // Refuse to write garbage. Better to keep the in-memory queue
            // and try again next call than to atomically overwrite a good
            // file with zero bytes.
            Log.scrobble.error("queue encode failed; not persisting (in-memory has \(snapshotCount, privacy: .public) records)")
            return
        }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            Log.scrobble.error("queue persist failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func enqueue(_ r: ScrobbleRecord) {
        records.append(r)
        persist()
    }

    func count() -> Int { records.count }

    /// Pulls up to `n` records for a batch submission attempt. Does not
    /// remove them. caller acknowledges with `acknowledge(ids:)` on success.
    func nextBatch(limit: Int = 50) -> [ScrobbleRecord] {
        Array(records.prefix(limit))
    }

    func acknowledge(ids: [UUID]) {
        let set = Set(ids)
        records.removeAll { set.contains($0.id) }
        persist()
    }

    /// Drop a poison-pill record we know Last.fm will never accept (e.g.
    /// missing artist after a corruption, or repeated 6/4 errors).
    func drop(id: UUID) {
        records.removeAll { $0.id == id }
        persist()
    }

    func markAttempted(ids: [UUID]) {
        let now = Date()
        for i in records.indices where ids.contains(records[i].id) {
            records[i].attempts += 1
            records[i].lastAttempt = now
        }
        persist()
    }

    /// Returns IDs of records whose attempts exceed `threshold`. caller can
    /// drop these as poison after enough retries.
    func idsExceedingAttempts(_ threshold: Int) -> [UUID] {
        records.filter { $0.attempts > threshold }.map(\.id)
    }

    /// Filesystem location of the queue file. for "Reveal in Finder" UX
    /// and developer log spelunking.
    func fileURL() -> URL { url }

    /// Empty the queue immediately (user-initiated "discard pending scrobbles").
    /// Returns the count discarded for confirmation UI.
    func clearAll() -> Int {
        let count = records.count
        records.removeAll()
        persist()
        return count
    }
}
