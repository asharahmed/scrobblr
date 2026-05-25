import Foundation
import AppKit

/// Fetches album artwork bytes via the public iTunes Search API.
///
/// Returns raw `Data` (not `NSImage`) because NSImage isn't Sendable in
/// Swift 6 — the consumer (PlaybackObserver, MainActor) constructs the
/// NSImage on its side. The actor only deals in transferable bytes.
///
/// Hardening:
///   * Validates the artwork URL is HTTPS with an `apple.com` / `mzstatic.com`
///     host (an attacker on a hostile network could otherwise return a `file://`
///     URL or arbitrary HTTP).
///   * Caps response size at 5 MB to prevent OOM on a poisoned response.
///   * Cache is bounded (LRU, 200 entries) so long sessions don't bloat memory.
///   * `inflight` is keyed via Tasks, so a second concurrent request for the
///     same track awaits the first instead of being rejected with nil.
actor ArtworkFetcher {
    static let shared = ArtworkFetcher()

    private struct Entry { let data: Data; let touched: Date }
    private var cache: [String: Entry] = [:]
    private let cacheLimit = 200

    private var inflight: [String: Task<Data?, Never>] = [:]

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 10
        c.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 64 * 1024 * 1024)
        return URLSession(configuration: c)
    }()

    private let maxBytes: Int = 5 * 1024 * 1024

    /// Look up artwork bytes for a track. `identity` keys the cache; the
    /// network query uses `(artist, title)`.
    func fetch(identity: String, artist: String, title: String) async -> Data? {
        if let hit = cache[identity] {
            cache[identity] = Entry(data: hit.data, touched: Date())
            return hit.data
        }
        if let existing = inflight[identity] {
            return await existing.value
        }
        let task = Task<Data?, Never> { [self] in
            await self.performFetch(identity: identity, artist: artist, title: title)
        }
        inflight[identity] = task
        let data = await task.value
        inflight.removeValue(forKey: identity)
        if let data {
            insertIntoCache(identity: identity, data: data)
        }
        return data
    }

    private func performFetch(identity: String, artist: String, title: String) async -> Data? {
        guard let url = searchURL(artist: artist, title: title) else { return nil }
        guard let artworkURL = await lookupArtworkURL(url) else { return nil }
        return await download(artworkURL)
    }

    // MARK: - Cache management

    private func insertIntoCache(identity: String, data: Data) {
        cache[identity] = Entry(data: data, touched: Date())
        // Bound: evict least-recently-touched until under the limit.
        if cache.count > cacheLimit {
            let toRemove = cache.count - cacheLimit
            let ordered = cache.sorted { $0.value.touched < $1.value.touched }
            for (k, _) in ordered.prefix(toRemove) {
                cache.removeValue(forKey: k)
            }
        }
    }

    // MARK: - HTTP

    private func searchURL(artist: String, title: String) -> URL? {
        // Cap term length — adversarial metadata can be arbitrarily long.
        let clamp: (String) -> String = { String($0.prefix(120)) }
        // Pre-escape `+` so the iTunes backend doesn't interpret it as space.
        let term = "\(clamp(artist)) \(clamp(title))"
            .replacingOccurrences(of: "+", with: "%2B")
        var c = URLComponents(string: "https://itunes.apple.com/search")
        c?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "media", value: "music"),
        ]
        return c?.url
    }

    private func lookupArtworkURL(_ url: URL) async -> URL? {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard data.count <= maxBytes else { return nil }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let results = json?["results"] as? [[String: Any]]
            guard let small = results?.first?["artworkUrl100"] as? String else { return nil }
            // Resolution upgrade: replace any `\d+x\d+(bb)?` size suffix.
            let regex = try NSRegularExpression(pattern: #"\d+x\d+(bb)?(?=\.[a-z]+$)"#)
            let range = NSRange(small.startIndex..., in: small)
            let large = regex.stringByReplacingMatches(
                in: small, range: range, withTemplate: "600x600bb"
            )
            guard let url = URL(string: large) else { return nil }
            return isSafeArtworkURL(url) ? url : nil
        } catch {
            return nil
        }
    }

    /// Whitelist: scheme must be HTTPS, host must end in `apple.com` or
    /// `mzstatic.com`. Without this an attacker on a hostile network could
    /// return `file://` URLs or arbitrary HTTP hosts.
    private func isSafeArtworkURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host.hasSuffix(".apple.com")
            || host.hasSuffix(".mzstatic.com")
            || host == "apple.com"
            || host == "mzstatic.com"
    }

    private func download(_ url: URL) async -> Data? {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let ctype = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            guard ctype.hasPrefix("image/") else { return nil }
            guard data.count <= maxBytes else { return nil }
            return data
        } catch {
            return nil
        }
    }

    func clearCache() {
        cache.removeAll()
        for (_, t) in inflight { t.cancel() }
        inflight.removeAll()
    }
}
