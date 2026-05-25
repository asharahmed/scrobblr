import Foundation
import AppKit
import OSLog

/// Bundles a redacted snapshot of recent unified-log entries + the queue
/// file + system info into a .zip on Desktop. Used by Settings → General →
/// "Export diagnostics" so users can attach something useful to bug reports
/// instead of being told to `log stream` in Terminal.
enum Diagnostics {
    /// Returns the URL of the produced zip, or nil if something failed.
    @MainActor
    static func exportToDesktop() async -> URL? {
        let fm = FileManager.default
        let desktop = (try? fm.url(for: .desktopDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: false))
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let ts = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let bundleDir = desktop.appendingPathComponent("scrobblr-diagnostics-\(ts)", isDirectory: true)
        do {
            try fm.createDirectory(at: bundleDir, withIntermediateDirectories: true)
            try await writeLogs(to: bundleDir.appendingPathComponent("log.txt"))
            writeSystemInfo(to: bundleDir.appendingPathComponent("system.txt"))
            copyQueueRedacted(to: bundleDir.appendingPathComponent("queue.json"))
            let zip = desktop.appendingPathComponent("scrobblr-diagnostics-\(ts).zip")
            try archive(bundleDir, to: zip)
            try? fm.removeItem(at: bundleDir)
            return zip
        } catch {
            Log.lifecycle.error("diagnostics export failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Sections

    private static func writeLogs(to url: URL) async throws {
        // Pull the last hour of our subsystem from the unified log.
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let since = store.position(date: Date().addingTimeInterval(-3600))
        let entries = try store.getEntries(at: since)
        var out = ""
        for entry in entries {
            guard let logEntry = entry as? OSLogEntryLog,
                  logEntry.subsystem == "app.scrobblr" else { continue }
            // Composed message respects the .private privacy markers. track
            // titles etc. arrive here as "<private>" already.
            out += "[\(logEntry.date)] [\(logEntry.category)] \(logEntry.composedMessage)\n"
        }
        if out.isEmpty {
            out = "(no app.scrobblr log entries in the last hour. try playing a track first)"
        }
        try out.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func writeSystemInfo(to url: URL) {
        let pi = ProcessInfo.processInfo
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let body = """
        Scrobblr \(v) (build \(b))
        macOS \(pi.operatingSystemVersionString)
        Hardware: \(pi.hostName) (\(pi.processorCount) cores, \(pi.physicalMemory / 1024 / 1024) MB RAM)
        Locale: \(Locale.current.identifier)
        Timezone: \(TimeZone.current.identifier)
        Generated: \(Date())
        """
        try? body.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Copies the queue file with sensitive bits redacted: artist + title +
    /// album → "<redacted>". Keeps shape, timestamps, attempt counts.
    private static func copyQueueRedacted(to url: URL) {
        let fm = FileManager.default
        guard let appSup = try? fm.url(for: .applicationSupportDirectory,
                                       in: .userDomainMask, appropriateFor: nil, create: false) else {
            return
        }
        let queuePath = appSup.appendingPathComponent("Scrobblr/scrobble-queue.json")
        guard let data = try? Data(contentsOf: queuePath),
              var records = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            try? Data("(no queue file)".utf8).write(to: url)
            return
        }
        for i in records.indices {
            records[i]["track"] = "<redacted>"
            records[i]["artist"] = "<redacted>"
            records[i]["album"] = "<redacted>"
            records[i]["albumArtist"] = "<redacted>"
        }
        let redacted = try? JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted])
        try? redacted?.write(to: url)
    }

    // MARK: - Zip

    private static func archive(_ dir: URL, to zip: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", dir.path, zip.path]
        try p.run()
        p.waitUntilExit()
    }
}
