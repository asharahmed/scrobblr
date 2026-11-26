# Security Policy

## Supported versions

Scrobblr is distributed as a single rolling release. Only the latest version,
available from [Releases](https://github.com/asharahmed/scrobblr/releases),
receives security fixes. Please update before reporting an issue.

## Reporting a vulnerability

Please do not open a public issue for security problems.

Report privately through one of:

- [GitHub private vulnerability reporting](https://github.com/asharahmed/scrobblr/security/advisories/new)
- Email: ashar@aahmed.ca

Include the affected version, your macOS version, and steps to reproduce.

You can expect an initial acknowledgment within 72 hours. Once a fix ships,
credit will be given in the release notes unless you prefer to remain anonymous.

## Scope

Scrobblr stores any per-user Last.fm key you add in the macOS Keychain and
communicates only with `ws.audioscrobbler.com` over HTTPS. The app also ships
with Scrobblr's own Last.fm application key; it is embedded in the binary by
design, identifies the app rather than the user, and cannot access an account
without that account's explicit browser approval. Reports involving credential handling,
the update channel, or the AppleScript automation surface are especially welcome.
