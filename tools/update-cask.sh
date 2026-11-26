#!/usr/bin/env bash
# Writes Casks/scrobblr.rb in the Homebrew tap for an already-published release.
#   ./tools/update-cask.sh 0.1.16
set -euo pipefail

VERSION="${1:?usage: update-cask.sh VERSION}"
TAG="v${VERSION}"
REPO=asharahmed/scrobblr
TAP=asharahmed/homebrew-tap
CASK_PATH=Casks/scrobblr.rb

cd "$(dirname "$0")/.."

# Hash what GitHub actually serves, not a local file that may have been rebuilt since.
SHA=$(gh api "repos/$REPO/releases/tags/$TAG" \
  --jq '.assets[] | select(.name == "Scrobblr.dmg") | .digest' | sed 's/^sha256://')
[[ ${#SHA} -eq 64 ]] || { echo "No Scrobblr.dmg digest on $TAG"; exit 1; }

CASK=$(sed -e "s/__VERSION__/$VERSION/" -e "s/__SHA256__/$SHA/" packaging/homebrew/scrobblr.rb)
EXISTING=$(gh api "repos/$TAP/contents/$CASK_PATH" --jq .sha 2>/dev/null || true)
# The contents API wants unwrapped base64; tr strips any line breaks base64 adds.
gh api -X PUT "repos/$TAP/contents/$CASK_PATH" \
  -f message="scrobblr $VERSION" \
  -f content="$(printf '%s\n' "$CASK" | base64 | tr -d '\n')" \
  ${EXISTING:+-f sha="$EXISTING"} >/dev/null
echo "==> Tap updated: brew install --cask asharahmed/tap/scrobblr"
