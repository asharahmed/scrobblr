#!/usr/bin/env bash
# Publishes a notarized .zip to GitHub Releases and emits a Sparkle appcast
# `<item>` block to paste into docs/appcast.xml.
#
# Usage:
#   ./tools/publish-release.sh 0.1.0 "First public release"
#
# Prereqs:
#   * release.sh has already produced dist/Scrobblr.zip (notarized + stapled)
#   * `gh` CLI installed and authenticated
#   * Sparkle SPM artifacts present (xcodebuild has resolved them at least once)

set -euo pipefail

VERSION="${1:?usage: publish-release.sh VERSION \"release notes\"}"
NOTES="${2:-}"
TAG="v${VERSION}"

cd "$(dirname "$0")/.."

ZIP="dist/Scrobblr.zip"
[[ -f "$ZIP" ]] || { echo "Run tools/release.sh first to produce $ZIP"; exit 1; }

SIGN_UPDATE=$(find ~/Library/Developer/Xcode/DerivedData \
    -path "*sparkle/Sparkle/bin/sign_update" 2>/dev/null | head -1)
[[ -x "$SIGN_UPDATE" ]] || {
  echo "sign_update not found in DerivedData — build the project once so SPM resolves Sparkle."
  exit 1
}

echo "==> Signing $ZIP with EdDSA"
SIG_LINE=$("$SIGN_UPDATE" "$ZIP")
# sign_update outputs: sparkle:edSignature="..." length="..."
echo "$SIG_LINE"

LENGTH=$(stat -f%z "$ZIP")
PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
DOWNLOAD_URL="https://github.com/asharahmed/scrobblr/releases/download/${TAG}/Scrobblr.zip"

cat <<EOF

==> Add this <item> to docs/appcast.xml (above the closing </channel>):

    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        ${NOTES}
      ]]></description>
      <enclosure
        url="${DOWNLOAD_URL}"
        length="${LENGTH}"
        type="application/octet-stream"
        ${SIG_LINE} />
    </item>

==> Then:
  1. git add docs/appcast.xml && git commit -m "appcast: ${TAG}" && git push
  2. gh release create ${TAG} ${ZIP} --notes "${NOTES}"

EOF
