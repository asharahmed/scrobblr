<h1 align="center">
  <img src="docs/icon-256.png" alt="Scrobblr" width="160" /><br>
  Scrobblr
</h1>

<p align="center">
  A polished Last.fm scrobbler for Apple Music on macOS.<br>
  Menu bar agent. SwiftUI. Notarized.
</p>

<p align="center">
  <a href="https://github.com/asharahmed/scrobblr/releases/latest">
    <img alt="Latest release" src="https://img.shields.io/github/v/release/asharahmed/scrobblr?style=flat-square&color=ec407a">
  </a>
  <a href="https://github.com/asharahmed/scrobblr/blob/main/LICENSE">
    <img alt="License" src="https://img.shields.io/github/license/asharahmed/scrobblr?style=flat-square&color=ec407a">
  </a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-ec407a?style=flat-square">
  <img alt="Apple Silicon + Intel" src="https://img.shields.io/badge/arch-Apple%20Silicon%20%2B%20Intel-ec407a?style=flat-square">
</p>

<p align="center">
  <a href="https://github.com/asharahmed/scrobblr/releases/latest/download/Scrobblr.dmg"><strong>↓ Download Scrobblr.dmg</strong></a>
  &nbsp;·&nbsp;
  <a href="#setup-end-to-end">Setup</a>
  &nbsp;·&nbsp;
  <a href="PRIVACY.md">Privacy</a>
  &nbsp;·&nbsp;
  <a href="DEVELOPMENT.md">Build from source</a>
</p>

---

## What it does

Scrobblr watches Apple Music for what you're playing and submits it to Last.fm — automatically, with proper offline handling, no nagging, no analytics, no servers in the middle. It lives in your menu bar (♪) and stays out of your way.

|   | |
|---|---|
| **Reliable** | Every play that passes Last.fm's 50% / 4-minute rule is queued and submitted. Plays from the last few weeks survive reboots, sleep, and offline stretches. |
| **Private** | No analytics. No author-controlled servers. Talks only to Last.fm and to Apple's anonymous iTunes Search API (for album art). |
| **Honest** | Custom Music access permission flow with pre-prompt explainers. Every credential lives in your Keychain. Logs redact track titles. |
| **Yours** | Bring your own Last.fm API key — no shared key that can get banned and break the app for everyone. |
| **Quiet** | Pause for an hour, ignore specific artists, override the scrobble threshold, skip podcasts / audiobooks / music videos by content type. |

## Install

1. **Download** [`Scrobblr.dmg`](https://github.com/asharahmed/scrobblr/releases/latest/download/Scrobblr.dmg) from the [latest release](https://github.com/asharahmed/scrobblr/releases/latest).
2. **Open the DMG** and drag **Scrobblr** to **Applications**.
3. **Launch it.** The welcome window walks you through setup in four steps. Total time: about a minute.

> **Important — move it to /Applications.** Running directly from `~/Downloads/` triggers macOS quarantine translocation, which breaks Launch-at-login and software updates. Scrobblr will warn you on first launch if it sees this.

## Setup, end to end

### 1 · Bring your own Last.fm API key

Scrobblr asks each user to register their own Last.fm application. It's free, takes 30 seconds, and keeps the app resilient — if a shared key got revoked for abuse, every install would break.

- Go to <https://www.last.fm/api/account/create>
- Fill in any **Application name** (e.g. *My Scrobblr*). Leave **Callback URL** and **Application homepage** blank.
- Submit. Last.fm shows you a 32-character **API Key** and 32-character **Shared Secret**.
- Paste both into the Scrobblr welcome window when prompted.

Both values are stored in your macOS Keychain and only sent to Last.fm.

### 2 · Sign in to Last.fm

Click **Sign in with Last.fm**. Your browser opens to Last.fm's approval page → click **Yes, allow access**. Scrobblr detects the approval and signs you in automatically.

### 3 · Allow access to Music.app

macOS will ask once: *"Scrobblr would like to control Music."* Click **Allow**. Scrobblr only ever reads — it cannot start, stop, or change tracks.

### 4 · Done

Scrobblr lives in the menu bar. Play music; scrobbles flow automatically once a track crosses Last.fm's threshold.

## Features

**Menu bar**
- Smooth-progress now-playing display with album art
- ♥ Love (and un-love) the current track
- Origin badge: Library, Apple Music, Stream, Podcast, Audiobook, Music Video
- Live status: scrobbled, queued, submitting, paused, needs re-auth

**Settings**
- **Account** — sign in / out, view profile, manage Last.fm app authorizations, replace API key
- **Playback** — Music access status, scrobble-threshold sliders (override Last.fm's 50% / 240s defaults), content filter (podcasts / audiobooks / music videos), ignored artists & tracks (exact or regex)
- **General** — launch at login, check for updates, replay welcome flow, export diagnostics, report a bug
- **Activity** — today / 7-day scrobble totals, pause scrobbling (30min / 1hr / 3hrs / tomorrow / indefinite), submission queue, recent scrobbles
- **About** — version, acknowledgments, privacy policy, license

**Engine**
- Distributed-notification-based playback detection (no MediaRemote private framework dependency — that's been locked down since macOS 15.4)
- Monotonic elapsed-time accumulator immune to wall-clock skew
- Per-record `ignoredMessage` handling — accepted records only are dropped from the queue
- Sleep / network-aware: pauses on system sleep, resumes on wake; pauses while offline, resumes on reconnect
- Sparkle 2 EdDSA-signed auto-updates

## How it works

Scrobblr uses two playback signals, since neither alone is enough on current macOS:

```
DistributedNotificationCenter         ──┐
  (com.apple.Music.playerInfo)          │
                                        ├──►  PlaybackObserver  ──►  ScrobbleEngine  ──►  Queue ──►  Last.fm
NSAppleScript poll (Music.app)        ──┘
  (1 Hz position, fallback metadata)
```

Architecture details, the macOS 26 `current track` regression workaround, and the build pipeline live in [`DEVELOPMENT.md`](DEVELOPMENT.md).

## Privacy

Scrobblr doesn't run a server. The author doesn't receive your data. Total outbound network surface:

- **Last.fm** (`ws.audioscrobbler.com`) — scrobbles + auth
- **Apple iTunes Search** (`itunes.apple.com`) — anonymous album-art lookup
- **GitHub Pages** — software update checks via Sparkle

Full policy: [PRIVACY.md](PRIVACY.md).

## Troubleshooting

**Nothing's playing, but Scrobblr says "Nothing playing".**
Distributed notifications fire on state *changes*. If music was already playing when Scrobblr launched, toggle pause/play to refresh state.

**The progress bar is stuck at 0.**
Music access was denied. Settings → Playback → Recheck. If shown as Denied, click **Open System Settings** and re-enable Scrobblr under Privacy & Security → Automation → Scrobblr → Music.

**Scrobbles aren't showing up on Last.fm.**
A track must play for ≥50% of its duration or ≥4 minutes (your threshold may be customized). Check Settings → Activity for queue and recent submissions. If "Re-authentication needed" appears, sign in again from Settings → Account.

**My account is on two Macs.**
Apple Music syncs queue across devices; both Macs running Scrobblr will double-scrobble. Run Scrobblr on only one.

**How do I see logs?**
```
log stream --predicate 'subsystem == "app.scrobblr"' --info
```
Categories: `playback`, `scrobble`, `api`, `auth`, `lifecycle`. User content (track titles, artists) is `private` in logs and appears redacted unless macOS private-data logging is enabled.

**How do I uninstall?**
Quit Scrobblr (menu bar → Quit), drag the app to Trash, then delete `~/Library/Application Support/Scrobblr/`. Remove the Keychain items by searching "Scrobblr" in Keychain Access. Revoke API access at <https://www.last.fm/settings/applications>.

## Reporting bugs

Open an issue at <https://github.com/asharahmed/scrobblr/issues>. Please include:

- macOS version (`sw_vers -productVersion`)
- Scrobblr version (Settings → About)
- A diagnostics bundle (Settings → General → Export diagnostics)

## License

MIT. See [LICENSE](LICENSE).

---

<p align="center">
  <sub>
    Last.fm is a registered trademark of CBS Interactive Inc. Apple Music is a trademark of Apple Inc.<br>
    Scrobblr is not affiliated with, endorsed by, or sponsored by either.
  </sub>
</p>
