import Foundation

/// Minimal Last.fm v2 client. just enough for desktop auth and scrobbling.
/// Endpoint: https://ws.audioscrobbler.com/2.0/. Always POSTs, always JSON.
actor LastFMClient {
    private var apiKey: String
    private var sharedSecret: String
    private let session: URLSession
    private let endpoint = URL(string: "https://ws.audioscrobbler.com/2.0/")!

    /// Session key (`sk`) obtained from `auth.getSession`. Stored in Keychain
    /// by the caller; injected here.
    private(set) var sessionKey: String?

    init(apiKey: String, sharedSecret: String, sessionKey: String? = nil, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.sharedSecret = sharedSecret
        self.sessionKey = sessionKey
        self.session = session
    }

    func setSessionKey(_ key: String?) { self.sessionKey = key }

    /// Rotate the API key + shared secret (e.g. after the user re-enters them
    /// in Settings → Account). Existing session key remains valid only if it
    /// was issued by the same key; otherwise callers should call `setSessionKey(nil)`.
    func updateCredentials(apiKey: String, sharedSecret: String) {
        self.apiKey = apiKey
        self.sharedSecret = sharedSecret
    }

    var currentAPIKey: String { apiKey }

    /// User-Agent reported to Last.fm. Includes the app version + macOS
    /// version + a contact URL so Last.fm support can route abuse traffic
    /// back to us rather than ban our shared API-key class wholesale.
    static let userAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "Scrobblr/\(version)+\(build) (macOS \(os.majorVersion).\(os.minorVersion); +https://github.com/asharahmed/scrobblr)"
    }()

    // MARK: - Auth

    /// Step 1 of the desktop auth flow: get a request token. Valid for 60min.
    func getToken() async throws -> String {
        let params = [
            "method": "auth.getToken",
            "api_key": apiKey,
        ]
        let json = try await call(params: params, signed: true)
        guard let token = json["token"] as? String else {
            throw LastFMError.decoding("auth.getToken: no token in response")
        }
        return token
    }

    /// User-facing URL the desktop app opens in a browser; the user logs in
    /// and approves, then `auth.getSession` consumes the token.
    func authorizationURL(token: String) -> URL {
        var c = URLComponents(string: "https://www.last.fm/api/auth/")!
        c.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "token", value: token),
        ]
        return c.url!
    }

    /// Step 3: exchange an approved token for a long-lived session key.
    /// Returns (sessionKey, username). The token is single-use.
    func getSession(token: String) async throws -> (sessionKey: String, username: String) {
        let params = [
            "method": "auth.getSession",
            "api_key": apiKey,
            "token": token,
        ]
        let json = try await call(params: params, signed: true)
        guard let s = json["session"] as? [String: Any],
              let key = s["key"] as? String,
              let name = s["name"] as? String else {
            throw LastFMError.decoding("auth.getSession: malformed response")
        }
        self.sessionKey = key
        return (key, name)
    }

    // MARK: - Scrobbling

    /// `track.updateNowPlaying`. fire once when playback starts.
    func updateNowPlaying(_ t: Track) async throws {
        guard let sk = sessionKey else { throw LastFMError.missingCredentials }
        var p: [String: String] = [
            "method": "track.updateNowPlaying",
            "api_key": apiKey,
            "sk": sk,
            "artist": t.artist,
            "track": t.title,
        ]
        if let a = t.album { p["album"] = a }
        if let aa = t.albumArtist { p["albumArtist"] = aa }
        if let n = t.trackNumber { p["trackNumber"] = String(n) }
        if let d = t.durationSeconds { p["duration"] = String(Int(d)) }
        _ = try await call(params: p, signed: true)
    }

    /// `track.scrobble`. batched, up to 50 per call.
    ///
    /// Returns per-record acceptance so the engine can selectively acknowledge
    /// accepted records and handle Last.fm's `ignoredMessage` codes (timestamp
    /// too old/new, daily limit, filtered artist) instead of silently treating
    /// all 200-OK responses as success.
    func scrobble(_ records: [ScrobbleRecord]) async throws -> [ScrobbleResult] {
        guard let sk = sessionKey else { throw LastFMError.missingCredentials }
        guard records.count <= 50 else {
            throw LastFMError.api(code: -1, message: "batch exceeds Last.fm max of 50")
        }
        guard !records.isEmpty else { return [] }

        var p: [String: String] = [
            "method": "track.scrobble",
            "api_key": apiKey,
            "sk": sk,
        ]
        for (i, r) in records.enumerated() {
            p["artist[\(i)]"] = r.artist
            p["track[\(i)]"] = r.track
            p["timestamp[\(i)]"] = String(r.timestamp)
            if let a = r.album { p["album[\(i)]"] = a }
            if let aa = r.albumArtist { p["albumArtist[\(i)]"] = aa }
            if let n = r.trackNumber { p["trackNumber[\(i)]"] = String(n) }
            if let d = r.durationSeconds { p["duration[\(i)]"] = String(d) }
        }
        let json = try await call(params: p, signed: true)
        return parseScrobbleResponse(json, records: records)
    }

    /// Parses the `scrobbles.scrobble[*].ignoredMessage` array. Last.fm
    /// returns either a single dict (when 1 scrobble) or an array. handle
    /// both. Records map positionally back to the input.
    private func parseScrobbleResponse(
        _ json: [String: Any], records: [ScrobbleRecord]
    ) -> [ScrobbleResult] {
        let container = json["scrobbles"] as? [String: Any] ?? [:]
        let raw = container["scrobble"]
        let entries: [[String: Any]] = {
            if let arr = raw as? [[String: Any]] { return arr }
            if let single = raw as? [String: Any] { return [single] }
            return []
        }()
        // If we got nothing back, treat as all accepted (server doesn't always
        // echo records). If counts mismatch, assume accepted for any missing.
        return records.enumerated().map { i, r in
            let entry = (i < entries.count) ? entries[i] : nil
            let im = entry?["ignoredMessage"] as? [String: Any]
            let codeString = (im?["code"] as? String) ?? "0"
            let code = Int(codeString) ?? 0
            let msg = (im?["#text"] as? String) ?? ""
            let acc: ScrobbleAcceptance = (code == 0)
                ? .accepted
                : .ignored(code: code, message: msg)
            return ScrobbleResult(id: r.id, acceptance: acc)
        }
    }

    /// `user.getRecentTracks`. count of tracks scrobbled since `from` (Unix
    /// seconds). Unsigned, anonymous-callable but we pass api_key. Used for
    /// the "today's scrobbles" stat in Activity. Returns 0 on any error
    /// rather than throwing; this is a soft stat, not protocol-critical.
    func recentTrackCount(username: String, since from: Int) async -> Int {
        let p: [String: String] = [
            "method": "user.getRecentTracks",
            "user": username,
            "api_key": apiKey,
            "from": String(from),
            "limit": "1",  // we only need the @attr.total
            "format": "json",
        ]
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = encodeForm(p)
        guard let (data, _) = try? await session.data(for: req),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let recent = json["recenttracks"] as? [String: Any],
              let attr = recent["@attr"] as? [String: Any],
              let total = (attr["total"] as? String).flatMap(Int.init)
        else { return 0 }
        return total
    }

    /// `track.love`. heart the current track.
    func love(artist: String, track: String) async throws {
        try await loveOrUnlove(method: "track.love", artist: artist, track: track)
    }

    /// `track.unlove`. un-heart a previously loved track.
    func unlove(artist: String, track: String) async throws {
        try await loveOrUnlove(method: "track.unlove", artist: artist, track: track)
    }

    private func loveOrUnlove(method: String, artist: String, track: String) async throws {
        guard let sk = sessionKey else { throw LastFMError.missingCredentials }
        let p: [String: String] = [
            "method": method,
            "api_key": apiKey, "sk": sk,
            "artist": artist, "track": track,
        ]
        _ = try await call(params: p, signed: true)
    }

    // MARK: - Transport

    private func call(params: [String: String], signed: Bool) async throws -> [String: Any] {
        var p = params
        if signed {
            p["api_sig"] = LastFMSignature.sign(p, secret: sharedSecret)
        }
        p["format"] = "json"

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = encodeForm(p)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw LastFMError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw LastFMError.transport("no HTTP response")
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let code = json["error"] as? Int {
            let msg = json["message"] as? String ?? ""
            throw LastFMError.api(code: code, message: msg)
        }
        if !(200...299).contains(http.statusCode) {
            throw LastFMError.http(status: http.statusCode)
        }
        return json
    }

    private func encodeForm(_ params: [String: String]) -> Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        let body = params.map { k, v in
            let ek = k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }
}
