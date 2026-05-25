# Privacy Policy

Scrobblr is a local utility that runs on your Mac. It does not run a server, and the author does not receive any data about your listening habits or your device.

## What Scrobblr reads

- **Currently playing track in Apple Music** — title, artist, album, duration, and persistent track identifier. Read from two sources:
  - macOS distributed notifications posted by Music.app (`com.apple.Music.playerInfo`)
  - Direct AppleScript queries to Music.app (only if you grant the one-time Automation permission)
- **Last.fm session key** — issued to your account when you sign in. Stored in your macOS Keychain, accessible only to Scrobblr on your machine.

Scrobblr never reads your Apple Music account credentials. macOS does not expose them to third-party apps.

## What Scrobblr sends, to whom, and why

| Destination | Data sent | Purpose |
| --- | --- | --- |
| `ws.audioscrobbler.com` (Last.fm) | Track title, artist, album, duration, play timestamp, your session key, your API signature | Scrobble submissions (`track.scrobble`, `track.updateNowPlaying`) |
| `itunes.apple.com` (Apple, anonymous) | Artist + title of the currently playing track | Album-art lookup via the public iTunes Search API |
| Your GitHub releases endpoint *(when update checking is enabled)* | Scrobblr version, macOS version | Software update check via Sparkle |

That's the entire outbound network surface. There are no analytics endpoints, no error-reporting endpoints, no author-controlled servers.

## What Scrobblr stores locally

- `~/Library/Application Support/Scrobblr/scrobble-queue.json` — a list of plays waiting to be submitted to Last.fm (deleted when accepted). The file is written with `completeFileProtection`.
- macOS Keychain entries under service `app.scrobblr.Scrobblr`:
  - `apiKey` and `sharedSecret` — your Last.fm developer credentials
  - `sessionKey` — your Last.fm bearer token
  - `username` — your Last.fm username (used to render the menu)
- `UserDefaults` flag `hasCompletedOnboarding` — boolean, no PII.
- Unified-log entries under subsystem `app.scrobblr` — categorised as `playback`, `scrobble`, `api`, `auth`, `lifecycle`. User-content strings (track titles, artists, usernames) are marked `private` and appear redacted in Console.app unless you explicitly enable private-data logging in macOS.

## What Scrobblr does not store

- It does not keep a permanent history of what you listened to. Past scrobbles live on Last.fm only; the on-device queue is only used to retry pending submissions.
- It does not record audio.
- It does not read other applications' data.

## Removing your data

To revoke Scrobblr's access to your Last.fm account: visit <https://www.last.fm/settings/applications> and remove the application authorization. This invalidates the session key Scrobblr stored.

To remove all local data: quit Scrobblr, then delete the app, the queue file at `~/Library/Application Support/Scrobblr/`, and the Keychain entries under service `app.scrobblr.Scrobblr` (Keychain Access → search for "Scrobblr").

## Third-party services

- **Last.fm** is operated by CBS Interactive Inc. Their privacy policy: <https://www.last.fm/legal/privacy>
- **iTunes Search API** is operated by Apple Inc. Their privacy policy: <https://www.apple.com/legal/privacy/>

## Changes

This policy is versioned with the app. Material changes will be called out in the GitHub release notes.

---

Last updated: 2026-05-25. Questions: file an issue on the GitHub repository.
