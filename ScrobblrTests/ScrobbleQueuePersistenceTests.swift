import XCTest
@testable import Scrobblr

/// Round-trips records through the on-disk JSON store and verifies corrupt
/// files are renamed aside instead of silently zeroing the queue.
final class ScrobbleQueuePersistenceTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scrobblr-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Redirect Application Support by setting HOME. simplest cross-test
        // isolation without rewriting the queue to accept an injected dir.
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func test_enqueue_and_acknowledge_round_trip() async {
        let q = ScrobbleQueue(filename: "test-roundtrip-\(UUID().uuidString).json")
        let track = Track(title: "T", artist: "A", album: nil, albumArtist: nil,
                          trackNumber: nil, durationSeconds: 200,
                          persistentID: "PID1", storeAdamID: nil, origin: .localFile)
        let r = ScrobbleRecord(track: track, startedAt: Date())
        await q.enqueue(r)
        let count = await q.count()
        XCTAssertEqual(count, 1)
        let batch = await q.nextBatch(limit: 50)
        XCTAssertEqual(batch.count, 1)
        await q.acknowledge(ids: batch.map(\.id))
        let afterAck = await q.count()
        XCTAssertEqual(afterAck, 0)
    }

    func test_corrupt_file_is_renamed_not_zeroed() async throws {
        let filename = "test-corrupt-\(UUID().uuidString).json"
        let q1 = ScrobbleQueue(filename: filename)
        let track = Track(title: "T", artist: "A", album: nil, albumArtist: nil,
                          trackNumber: nil, durationSeconds: 200,
                          persistentID: "PID1", storeAdamID: nil, origin: .localFile)
        await q1.enqueue(ScrobbleRecord(track: track, startedAt: Date()))

        let baseDir = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("Scrobblr", isDirectory: true)
        let path = baseDir.appendingPathComponent(filename)
        // Corrupt it.
        try Data("not json".utf8).write(to: path)

        // Reload. should detect corruption, rename aside.
        let q2 = ScrobbleQueue(filename: filename)
        let reloadedCount = await q2.count()
        XCTAssertEqual(reloadedCount, 0)
        let renamed = try FileManager.default.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains(filename) && $0.pathExtension.hasPrefix("bad-") }
        XCTAssertFalse(renamed.isEmpty, "expected at least one .bad-<ts> file")

        // Cleanup
        try? FileManager.default.removeItem(at: path)
        for r in renamed { try? FileManager.default.removeItem(at: r) }
    }
}
