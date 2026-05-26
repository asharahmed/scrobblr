import Foundation

/// Models + API calls for the Stats window. All `user.getTop*` methods are
/// signed but anonymous-callable (no session key). Returns empty arrays on
/// any error; stats are soft data, not protocol-critical.

public enum LastFMPeriod: String, CaseIterable, Sendable, Identifiable {
    case sevenDays   = "7day"
    case oneMonth    = "1month"
    case threeMonths = "3month"
    case sixMonths   = "6month"
    case oneYear     = "12month"
    case overall     = "overall"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .sevenDays:   "7 days"
        case .oneMonth:    "1 month"
        case .threeMonths: "3 months"
        case .sixMonths:   "6 months"
        case .oneYear:     "1 year"
        case .overall:     "All time"
        }
    }
}

public struct TopTrack: Sendable, Identifiable, Hashable {
    public let id = UUID()
    public let rank: Int
    public let title: String
    public let artist: String
    public let playCount: Int
    public let url: URL?
    public let mbid: String?
}

public struct TopArtist: Sendable, Identifiable, Hashable {
    public let id = UUID()
    public let rank: Int
    public let name: String
    public let playCount: Int
    public let url: URL?
}

public struct TopAlbum: Sendable, Identifiable, Hashable {
    public let id = UUID()
    public let rank: Int
    public let title: String
    public let artist: String
    public let playCount: Int
    public let url: URL?
    public let imageURL: URL?
}

/// One scrobble surfaced by `user.getRecentTracks`. Used for the
/// listening-heatmap aggregation.
public struct RecentScrobble: Sendable, Hashable {
    public let artist: String
    public let title: String
    public let playedAt: Date
}

/// What Last.fm thinks the user is currently scrobbling, on any device.
/// Populated from `user.getRecentTracks?limit=1` when the first row has
/// `@attr.nowplaying="true"`.
public struct RemoteNowPlaying: Sendable, Equatable {
    public let artist: String
    public let title: String
    public let album: String?
    public let imageURL: URL?
}

extension LastFMClient {

    // MARK: - Remote now-playing

    /// Asks Last.fm what (if anything) the user is currently scrobbling on
    /// any device. Returns nil when no client is actively scrobbling.
    func nowPlayingOnLastFM(username: String) async -> RemoteNowPlaying? {
        let p: [String: String] = [
            "method": "user.getRecentTracks",
            "user": username,
            "api_key": apiKey,
            "limit": "1",
            "format": "json",
        ]
        guard let json = await unsignedGET(p),
              let container = json["recenttracks"] as? [String: Any]
        else { return nil }
        let entries: [[String: Any]] = {
            if let arr = container["track"] as? [[String: Any]] { return arr }
            if let single = container["track"] as? [String: Any] { return [single] }
            return []
        }()
        guard let first = entries.first else { return nil }
        // Last.fm marks the now-playing row with @attr.nowplaying="true".
        let attr = first["@attr"] as? [String: Any]
        let nowPlaying = (attr?["nowplaying"] as? String) == "true"
        guard nowPlaying else { return nil }
        let title = (first["name"] as? String) ?? ""
        let artist: String = {
            if let a = first["artist"] as? [String: Any] {
                return (a["name"] as? String) ?? (a["#text"] as? String) ?? ""
            }
            return ""
        }()
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        let album: String? = {
            if let a = first["album"] as? [String: Any] {
                let s = (a["#text"] as? String) ?? (a["name"] as? String) ?? ""
                return s.isEmpty ? nil : s
            }
            return nil
        }()
        let imageURL: URL? = {
            guard let images = first["image"] as? [[String: Any]] else { return nil }
            let preferred = images.last(where: { ($0["size"] as? String) == "extralarge" })
                ?? images.last(where: { ($0["size"] as? String) == "large" })
                ?? images.last
            guard let str = preferred?["#text"] as? String, !str.isEmpty,
                  !str.contains("2a96cbd8b46e442fc41c2b86b821562f")
            else { return nil }
            return URL(string: str)
        }()
        return RemoteNowPlaying(artist: artist, title: title, album: album, imageURL: imageURL)
    }

    // MARK: - Artwork fallback via track.getInfo

    /// `track.getInfo` artwork URL. Used as a second-chance lookup when
    /// iTunes Search has no result for a track. Last.fm's image array
    /// sometimes contains placeholder URLs ending in `2a96cbd8b46e442fc41c2b86b821562f.png`;
    /// callers should detect and skip those.
    func trackInfoArtworkURL(artist: String, title: String) async -> URL? {
        let p: [String: String] = [
            "method": "track.getInfo",
            "api_key": apiKey,
            "artist": artist,
            "track": title,
            "format": "json",
        ]
        guard let json = await unsignedGET(p),
              let track = json["track"] as? [String: Any],
              let album = track["album"] as? [String: Any],
              let images = album["image"] as? [[String: Any]]
        else { return nil }
        let preferred = images.last(where: { ($0["size"] as? String) == "extralarge" })
            ?? images.last(where: { ($0["size"] as? String) == "large" })
            ?? images.last
        guard let str = preferred?["#text"] as? String, !str.isEmpty,
              // Skip Last.fm's "no artwork" placeholder fingerprint.
              !str.contains("2a96cbd8b46e442fc41c2b86b821562f")
        else { return nil }
        return URL(string: str)
    }

    // MARK: - Top tracks

    func topTracks(username: String, period: LastFMPeriod, limit: Int = 50) async -> [TopTrack] {
        let p: [String: String] = [
            "method": "user.getTopTracks",
            "user": username,
            "api_key": apiKey,
            "period": period.rawValue,
            "limit": String(limit),
            "format": "json",
        ]
        guard let json = await unsignedGET(p),
              let container = json["toptracks"] as? [String: Any]
        else { return [] }
        let entries = normalizeArray(container["track"])
        return entries.compactMap { row in
            guard let title = row["name"] as? String else { return nil }
            let artist: String = {
                if let a = row["artist"] as? [String: Any] {
                    return (a["name"] as? String) ?? ""
                }
                return ""
            }()
            let plays = Int((row["playcount"] as? String) ?? "0") ?? 0
            let rank = Int(((row["@attr"] as? [String: Any])?["rank"] as? String) ?? "0") ?? 0
            let url = (row["url"] as? String).flatMap { URL(string: $0) }
            return TopTrack(rank: rank, title: title, artist: artist,
                            playCount: plays, url: url,
                            mbid: row["mbid"] as? String)
        }
    }

    // MARK: - Top artists

    func topArtists(username: String, period: LastFMPeriod, limit: Int = 50) async -> [TopArtist] {
        let p: [String: String] = [
            "method": "user.getTopArtists",
            "user": username,
            "api_key": apiKey,
            "period": period.rawValue,
            "limit": String(limit),
            "format": "json",
        ]
        guard let json = await unsignedGET(p),
              let container = json["topartists"] as? [String: Any]
        else { return [] }
        let entries = normalizeArray(container["artist"])
        return entries.compactMap { row in
            guard let name = row["name"] as? String else { return nil }
            let plays = Int((row["playcount"] as? String) ?? "0") ?? 0
            let rank = Int(((row["@attr"] as? [String: Any])?["rank"] as? String) ?? "0") ?? 0
            let url = (row["url"] as? String).flatMap { URL(string: $0) }
            return TopArtist(rank: rank, name: name, playCount: plays, url: url)
        }
    }

    // MARK: - Top albums

    func topAlbums(username: String, period: LastFMPeriod, limit: Int = 50) async -> [TopAlbum] {
        let p: [String: String] = [
            "method": "user.getTopAlbums",
            "user": username,
            "api_key": apiKey,
            "period": period.rawValue,
            "limit": String(limit),
            "format": "json",
        ]
        guard let json = await unsignedGET(p),
              let container = json["topalbums"] as? [String: Any]
        else { return [] }
        let entries = normalizeArray(container["album"])
        return entries.compactMap { row in
            guard let title = row["name"] as? String else { return nil }
            let artist: String = {
                if let a = row["artist"] as? [String: Any] {
                    return (a["name"] as? String) ?? ""
                }
                return ""
            }()
            let plays = Int((row["playcount"] as? String) ?? "0") ?? 0
            let rank = Int(((row["@attr"] as? [String: Any])?["rank"] as? String) ?? "0") ?? 0
            let url = (row["url"] as? String).flatMap { URL(string: $0) }
            // Last.fm's "image" array often contains placeholder graphics for
            // missing artwork; we still grab the largest size and let the
            // view fall back to iTunes Search on placeholder detection.
            let img: URL? = {
                guard let arr = row["image"] as? [[String: Any]] else { return nil }
                let large = arr.last(where: { ($0["size"] as? String) == "extralarge" })
                    ?? arr.last(where: { ($0["size"] as? String) == "large" })
                    ?? arr.last
                guard let str = large?["#text"] as? String, !str.isEmpty else { return nil }
                return URL(string: str)
            }()
            return TopAlbum(rank: rank, title: title, artist: artist,
                            playCount: plays, url: url, imageURL: img)
        }
    }

    // MARK: - Heatmap data (recent tracks paged)

    /// Pull recent scrobbles for the heatmap. Pages up to `pages` × 200 rows.
    /// 90 days of moderate listening fits in ~2-3 pages; heavy listeners may
    /// need more but stale pages give back stale data, so we stop when we
    /// see a scrobble older than `since`.
    func recentScrobbles(username: String, since: Date, pages: Int = 5) async -> [RecentScrobble] {
        var all: [RecentScrobble] = []
        for page in 1...pages {
            let p: [String: String] = [
                "method": "user.getRecentTracks",
                "user": username,
                "api_key": apiKey,
                "limit": "200",
                "page": String(page),
                "from": String(Int(since.timeIntervalSince1970)),
                "format": "json",
            ]
            guard let json = await unsignedGET(p),
                  let container = json["recenttracks"] as? [String: Any]
            else { break }
            let entries = normalizeArray(container["track"])
            if entries.isEmpty { break }
            var pageRows: [RecentScrobble] = []
            for row in entries {
                // Skip the synthetic "now playing" row, which has no `date`.
                guard let dateInfo = row["date"] as? [String: Any],
                      let uts = dateInfo["uts"] as? String,
                      let secs = Double(uts) else { continue }
                let when = Date(timeIntervalSince1970: secs)
                guard when >= since else { return all }
                let title = (row["name"] as? String) ?? ""
                let artistName: String = {
                    if let a = row["artist"] as? [String: Any] {
                        return (a["name"] as? String) ?? (a["#text"] as? String) ?? ""
                    }
                    return ""
                }()
                pageRows.append(RecentScrobble(artist: artistName, title: title, playedAt: when))
            }
            all.append(contentsOf: pageRows)
            if pageRows.count < 200 { break }
        }
        return all
    }

    // MARK: - Transport helpers

    /// Unsigned GET-style call for read-only public-ish stats. We still POST
    /// with `format=json` since the endpoint accepts both and we already have
    /// the form encoder.
    private func unsignedGET(_ params: [String: String]) async -> [String: Any]? {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = encodeForm(params)
        guard let (data, _) = try? await session.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if (json["error"] as? Int) != nil { return nil }
        return json
    }

    /// Last.fm wraps single-item lists in a dict rather than a 1-element array.
    /// Normalize both shapes to `[[String: Any]]`.
    private func normalizeArray(_ raw: Any?) -> [[String: Any]] {
        if let arr = raw as? [[String: Any]] { return arr }
        if let single = raw as? [String: Any] { return [single] }
        return []
    }
}
