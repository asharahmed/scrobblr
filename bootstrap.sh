#!/usr/bin/env bash
set -euo pipefail

# Bootstraps the Scrobblr project: installs xcodegen if needed, generates
# Scrobblr.xcodeproj, and creates a local Secrets.swift stub for your
# Last.fm API key + shared secret.

cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "==> Installing xcodegen via Homebrew"
    brew install xcodegen
  else
    echo "ERROR: xcodegen not installed and Homebrew not found." >&2
    echo "Install Homebrew (https://brew.sh) or xcodegen manually, then re-run." >&2
    exit 1
  fi
fi

SECRETS=Scrobblr/Config/Secrets.swift
if [[ ! -f "$SECRETS" ]]; then
  echo "==> Creating $SECRETS stub (edit before first run)"
  mkdir -p "$(dirname "$SECRETS")"
  cat > "$SECRETS" <<'EOF'
// Secrets.swift — gitignored. Fill in the values you got from
// https://www.last.fm/api/account/create and re-run xcodegen.
enum Secrets {
    static let lastFMAPIKey = "REPLACE_ME"
    static let lastFMSharedSecret = "REPLACE_ME"
}
EOF
fi

echo "==> Generating Xcode project"
xcodegen generate

echo
echo "Done. Open Scrobblr.xcodeproj in Xcode."
echo "Reminder: fill in $SECRETS before authenticating with Last.fm."
