# Scrobblr

A polished Last.fm scrobbler for Apple Music on macOS. Lives in your menu bar, watches what Music.app is playing, and posts your scrobbles to Last.fm — automatically, with proper offline handling.

<p align="center">
  <em>Menu bar agent · macOS 14+ · Apple Silicon &amp; Intel · notarized</em>
</p>

## Download

Grab the latest release from <https://github.com/asharahmed/scrobblr/releases/latest>.

1. Unzip and drag **Scrobblr.app** to your **Applications** folder.
2. Double-click to launch. The welcome window guides you through setup.
3. Quit isn't necessary — Scrobblr lives in the menu bar (♪) and auto-launches if you let it.

> **Important: move it to /Applications.** Running from `~/Downloads/` triggers macOS quarantine translocation, which breaks the "Launch at login" toggle and update checks. Scrobblr will warn you on first launch if it sees this.

## Setup, end to end

### 1 · Bring your own Last.fm API key

Scrobblr asks each user to register their own Last.fm application. It's free, takes 30 seconds, and keeps the app resilient — if someone else's key gets revoked for abuse, yours keeps working.

1. Go to <https://www.last.fm/api/account/create>.
2. Fill in any **Application name** (e.g. "My Scrobblr"). Leave **Callback URL** and **Application homepage** blank.
3. Submit. Last.fm shows you a 32-character **API Key** and a 32-character **Shared Secret**.
4. Paste both into the Scrobblr welcome window when prompted.

The values are stored in your macOS Keychain, never sent anywhere except to Last.fm.

### 2 · Sign in to Last.fm

Click **Sign in with Last.fm**. Your browser opens to Last.fm's approval page; click **Yes, allow access**. Scrobblr detects the approval and signs you in automatically — no need to come back and click anything.

### 3 · Allow access to Music.app

macOS will ask once: "Scrobblr would like to control Music." Click **Allow**. This lets Scrobblr read what's playing — it cannot start, stop, or change tracks.

### 4 · Done

Scrobblr is now resident in your menu bar. Play music; scrobbles flow automatically once a track passes Last.fm's threshold (50% played or 4 minutes, whichever comes first).

## How it works

| Behaviour | Detail |
|---|---|
| **What it scrobbles** | Library tracks and Apple Music catalog tracks |
| **What it skips** | Apple Music Radio, internet radio, tracks under 30 seconds, anything paused for >5s before 50%/4min crosses |
| **What it sends to Last.fm** | Track title, artist, album, duration, play timestamp |
| **What it sends to Apple** | Track artist + title (only for anonymous album-art lookup via iTunes Search) |
| **Offline behaviour** | Plays are queued locally and submitted in batches when you reconnect |
| **Sleep behaviour** | The submission queue pauses on system sleep and resumes on wake |

The menu bar dropdown shows the currently playing track, a smooth progress bar, your scrobble queue status, and the last play submitted. Click the gear icon for full settings.

## Privacy

Scrobblr doesn't run a server. The author doesn't receive your listening history.

Outbound traffic in total:

- **Last.fm**: scrobbles + auth (`ws.audioscrobbler.com`)
- **Apple iTunes Search**: anonymous album-art lookup (`itunes.apple.com`)
- **GitHub Pages**: update checks for new Scrobblr versions

That's it. No analytics, no error reporting, no third-party services.

Full policy: [PRIVACY.md](PRIVACY.md).

## Updates

Scrobblr checks for updates automatically once a day (and manually via Settings → General → Check now). Updates are EdDSA-signed and only installed if they verify against the public key embedded in your build — no man-in-the-middle can push a malicious version.

## Troubleshooting

**Nothing's playing — but the menu shows "Nothing playing".**
Open Apple Music and start a track. Distributed notifications fire only on state changes, so Scrobblr can't see a track that was already playing when you launched it; toggling pause/play will refresh state.

**The progress bar doesn't move / is stuck at 0.**
Music access permission was probably denied. Settings → Playback → Recheck. If it shows Denied, click **Open System Settings** and re-enable Scrobblr under Privacy &amp; Security → Automation → Scrobblr → Music.

**Scrobbles aren't appearing on Last.fm.**
A track must play for ≥50% of its duration or ≥4 minutes before it scrobbles. Check Settings → Activity to see your queue and recent submissions. If "Re-authentication needed" appears, sign in again from Settings → Account.

**My account is on two Macs.**
Apple Music syncs your queue across devices; if both Macs run Scrobblr, plays may be submitted twice. Run Scrobblr on only one machine, or accept the duplicates.

**Where do I see logs?**
```
log stream --predicate 'subsystem == "app.scrobblr"' --info
```
Categories: `playback`, `scrobble`, `api`, `auth`, `lifecycle`. User-content strings (track titles, artists) are redacted unless you enable private-data logging in macOS.

**How do I uninstall?**
Quit Scrobblr (menu bar → Quit), drag the app to Trash, then delete `~/Library/Application Support/Scrobblr/`. Remove the Keychain items by searching "Scrobblr" in Keychain Access. Revoke API access at <https://www.last.fm/settings/applications>.

## Building from source

See [DEVELOPMENT.md](DEVELOPMENT.md).

## Reporting bugs

File an issue at <https://github.com/asharahmed/scrobblr/issues>. Please include:

- macOS version (`sw_vers -productVersion`)
- Scrobblr version (Settings → About)
- Last 5 minutes of `log stream --predicate 'subsystem == "app.scrobblr"'` if you can

## Acknowledgments

- [Last.fm Web Services](https://www.last.fm/api) for the scrobble API
- [Sparkle](https://sparkle-project.org) for software updates
- Apple's iTunes Search API for album art

---

Last.fm is a registered trademark of CBS Interactive Inc. Apple Music is a trademark of Apple Inc. Scrobblr is not affiliated with, endorsed by, or sponsored by either.
