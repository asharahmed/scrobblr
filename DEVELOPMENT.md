# Scrobblr — development notes

Internal docs. For end-user setup see [README.md](README.md).

## Architecture

```
DistributedNotificationCenter   ──┐
  (com.apple.Music.playerInfo)    │
                                  ├──►  PlaybackObserver  ──►  ScrobbleEngine  ──►  ScrobbleQueue
NSAppleScript poll (Music.app)  ──┘                                                       │
  (position oracle, ~1 Hz)                                                                ▼
                                                                                    LastFMClient
                                                                                    (URLSession +
                                                                                     CryptoKit MD5)
```

Two playback signals because neither is sufficient alone:

- **`com.apple.Music.playerInfo` distributed notification** drives state transitions. Carries `Player State`, `Name`, `Artist`, `Album`, `Total Time` (ms), `Track Number`, `PersistentID`, `Store URL`, `Location`, `Stream Title/URL`. Music.app posts it directly — unaffected by the macOS 15.4 MediaRemote clampdown.
- **NSAppleScript polling of Music.app** (1 Hz while playing, paused otherwise) supplies precise position info for the progress bar and backfills metadata that notifications may omit. Each property is read via `… of current track` to sidestep the macOS 26 `-1728` regression for non-library tracks (FB19908171).

We intentionally do **not** depend on the private `MediaRemote` framework. Apple locked it behind a private entitlement in macOS 15.4 (April 2025).

### Scrobble rules (`ScrobbleRules.swift`)

Per [Last.fm's spec](https://www.last.fm/api/scrobbling):

- Track must be ≥30 s
- Scrobble when *elapsed listening time* ≥ 50% OR ≥240 s (whichever first)
- Elapsed time runs on `ContinuousClock`, immune to wall-clock skew
- Plays <5 s are debounced as skips
- Streams (Apple Music Radio, internet radio) never scrobble

### Network resilience

- Queue persisted at `~/Library/Application Support/Scrobblr/scrobble-queue.json` with `completeFileProtection`
- Batches of up to 50 (Last.fm's max-per-call)
- Per-record `ignoredMessage` codes from `track.scrobble` parsed: code 0 → ack, 1/2/3 → drop, 4 → retry, 5 → pause until UTC midnight
- Exponential backoff on transient errors (HTTP 5xx, Last.fm codes 11/16/29)
- Code 9 (invalid session) pauses the queue and surfaces a re-auth prompt
- Permanent batch errors mark attempts; records past 5 attempts are dropped

## Source layout

```
Scrobblr/
├── App/                ScrobblrApp + AppCoordinator + AppDelegate
├── Models/             Track, PlaybackState, ScrobbleRecord, ScrobbleResult
├── Playback/           DistributedNotificationSource, MusicAppBridge, PlaybackObserver, ArtworkFetcher
├── LastFM/             LastFMClient, LastFMSignature, LastFMError
├── Scrobble/           ScrobbleEngine, ScrobbleQueue, ScrobbleRules
├── Storage/            Keychain
├── Util/               Log, LoginItem, SystemMonitor, AutomationPermission, Updater
├── UI/                 MenuBarContent, SettingsView, Onboarding/, Components/
├── Config/             Credentials (Keychain-backed), Secrets (#if DEBUG only, gitignored)
└── Assets.xcassets/
```

## Build prerequisites

- Xcode 16+ (project targets Swift 6 strict concurrency)
- macOS 14+ to run, but builds on any host with recent Xcode
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Bootstrap

```bash
./bootstrap.sh
```

Installs xcodegen if missing, generates `Scrobblr.xcodeproj`, scaffolds `Scrobblr/Config/Secrets.swift` (gitignored). Open the project and ⌘R to run.

In DEBUG builds, if you've put real values in `Secrets.swift`, they'll be seeded into the Keychain on first launch so you skip the BYOK onboarding step. Release builds never compile `Secrets.swift` (the whole enum is wrapped in `#if DEBUG`).

## Shipping a release

### One-time setup

1. **Developer ID Application certificate** installed in your login keychain (`security find-identity -v -p codesigning`)
2. **App-specific password** from <https://account.apple.com/account/manage>
3. **Notarytool credentials**:
   ```bash
   xcrun notarytool store-credentials AC_PROFILE \
     --apple-id you@you.com --team-id YOUR_TEAM_ID --password app-specific-pw
   ```
4. **Sparkle EdDSA keypair** (one-time):
   ```bash
   ~/Library/Developer/Xcode/DerivedData/Scrobblr-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
   ```
   This stores the private key in your login keychain and prints the public key. The public key is already in `project.yml` as `SUPublicEDKey`. If you ever lose your keychain, you must rotate and ship a build with the new public key — old installs won't be able to verify new updates.

### Release build

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
export AC_KEYCHAIN_PROFILE=AC_PROFILE
./tools/release.sh
```

Builds Release config, re-signs the embedded Sparkle helpers (Updater.app, Autoupdate, XPC services) with your Developer ID + secure timestamp + hardened runtime, submits to Apple's notary service, staples the ticket, and re-zips. Output: `dist/Scrobblr.app` + `dist/Scrobblr.zip`.

### Publishing a release

```bash
./tools/publish-release.sh 0.1.0 "First public release"
```

Signs the zip with `sign_update` (EdDSA over the file contents) and prints an appcast `<item>` block. Workflow:

1. Run `tools/release.sh` to produce `dist/Scrobblr.zip`
2. Run `tools/publish-release.sh VERSION "notes"` — it prints the appcast snippet
3. Paste the snippet into `docs/appcast.xml` (above `</channel>`)
4. `git add docs/appcast.xml && git commit -m "appcast: vX.Y.Z" && git push`
5. `gh release create vX.Y.Z dist/Scrobblr.zip --notes "..."`

The `docs/` folder is published via GitHub Pages at `https://asharahmed.github.io/scrobblr/appcast.xml`. To enable: repo Settings → Pages → Source: `main` branch / `/docs` folder.

## Regenerating the icon

```bash
swift tools/generate-icon.swift
```

Rewrites `Scrobblr/Assets.xcassets/AppIcon.appiconset/`. Source is `tools/generate-icon.swift` — edit the gradient/symbol there.

## Debug logging

```bash
log stream --predicate 'subsystem == "app.scrobblr"' --info
```

Categories: `playback`, `scrobble`, `api`, `auth`, `lifecycle`. User-content strings (track titles, artists, usernames) are marked `private` in source and appear redacted in Console.app unless you enable private-data logging in macOS.

## Tests

```bash
xcodebuild -project Scrobblr.xcodeproj -scheme Scrobblr test
```

6 suites: `LastFMSignatureTests`, `LastFMErrorClassificationTests`, `ScrobbleRulesTests`, `ScrobbleResultParseTests`, `TrackIdentityTests`, `ScrobbleQueuePersistenceTests`. Coverage gaps documented in audit findings — the state-machine paths (ScrobbleEngine, PlaybackObserver) need mocks before being properly tested.

## Known platform caveats

- **macOS 26 (Tahoe) `current track` regression** (FB19908171): non-library tracks throw `-1728` from AppleScript when bound to an intermediate variable. Mitigated by reading every property via direct `… of current track` access.
- **MediaRemote clampdown** (macOS 15.4, April 2025): private framework now requires an Apple-only entitlement. Scrobblr never depended on it; we use distributed notifications + AppleScript instead.
- **Last.fm rate limits**: documented at ~2800 scrobbles/day per user and 5 req/s per IP averaged. Batching means we'd need 56 batches of 50 to hit the daily cap.
