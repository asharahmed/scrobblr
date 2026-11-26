#!/usr/bin/env bash
# Builds, signs, and notarizes a release of Scrobblr.
#
# Required env vars:
#   DEVELOPER_ID_APPLICATION   "Developer ID Application: Your Name (TEAMID)"
#   AC_KEYCHAIN_PROFILE        a notarytool keychain profile name configured via
#                              `xcrun notarytool store-credentials AC_PROFILE \
#                                  --apple-id you@you --team-id TEAMID --password app-specific-pw`
#
# Output: dist/Scrobblr.app and dist/Scrobblr.zip (notarized + stapled).

set -euo pipefail
cd "$(dirname "$0")/.."

: "${DEVELOPER_ID_APPLICATION:?set DEVELOPER_ID_APPLICATION}"
: "${AC_KEYCHAIN_PROFILE:?set AC_KEYCHAIN_PROFILE}"

DIST=dist
rm -rf "$DIST" build
mkdir -p "$DIST"

echo "==> Regenerating Xcode project"
xcodegen generate >/dev/null

echo "==> Building Release"
xcodebuild \
  -project Scrobblr.xcodeproj \
  -scheme Scrobblr \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  CODE_SIGN_STYLE=Manual \
  build | tail -20

APP="build/Build/Products/Release/Scrobblr.app"
[[ -d "$APP" ]] || { echo "build failed: $APP not found"; exit 1; }

# Since 1 December 2026 Last.fm only accepts API keys whose owner has Pro,
# so a release without Scrobblr's own key cannot onboard free users. Warn
# but keep going: forks legitimately ship without it.
#
# Both halves are required. AppCredentials.isConfigured rejects a missing or
# malformed value, so a valid key with a broken secret still falls back to
# manual onboarding.
hex32() {
  plutil -extract "$1" raw "$APP/Contents/Info.plist" 2>/dev/null | grep -Eqi '^[0-9a-f]{32}$'
}
if ! hex32 LastFMAppAPIKey || ! hex32 LastFMAppSharedSecret; then
  echo "WARNING: no valid LASTFM_APP_API_KEY / LASTFM_APP_SHARED_SECRET pair in this build."
  echo "         Put both in Scrobblr/Config/AppKey.local.xcconfig before shipping."
  echo "         Users of this build would have to register their own key, which needs Last.fm Pro."
fi

echo "==> Re-signing Sparkle helpers with Developer ID"
# Sparkle ships pre-signed nested binaries (Autoupdate, Updater.app, XPC
# services). Apple's notary requires every binary in the bundle to carry our
# Developer ID + secure timestamp + hardened runtime. Re-sign them deepest-
# first, then sign the outer app last.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE" ]]; then
  for helper in \
    "$SPARKLE/Versions/B/XPCServices/Downloader.xpc" \
    "$SPARKLE/Versions/B/XPCServices/Installer.xpc" \
    "$SPARKLE/Versions/B/Autoupdate" \
    "$SPARKLE/Versions/B/Updater.app" \
    "$SPARKLE/Versions/B"; do
    if [[ -e "$helper" ]]; then
      codesign --force --sign "$DEVELOPER_ID_APPLICATION" \
               --timestamp --options runtime \
               "$helper"
    fi
  done
  # Re-sign the outer app to incorporate the new framework hashes.
  codesign --force --sign "$DEVELOPER_ID_APPLICATION" \
           --timestamp --options runtime \
           --entitlements "Scrobblr/Scrobblr.entitlements" \
           "$APP"
fi

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Zipping for notarization"
ZIP="$DIST/Scrobblr.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Submitting to notary (this can take a few minutes)"
xcrun notarytool submit "$ZIP" \
  --keychain-profile "$AC_KEYCHAIN_PROFILE" \
  --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$APP"

echo "==> Re-zipping stapled app"
rm "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
cp -R "$APP" "$DIST/"

echo "==> Building DMG"
DMG="$DIST/Scrobblr.dmg"
DMG_STAGE="$DIST/dmg-stage"
rm -rf "$DMG_STAGE" "$DMG"
mkdir -p "$DMG_STAGE"
cp -R "$APP" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create \
    -volname "Scrobblr" \
    -srcfolder "$DMG_STAGE" \
    -ov -format UDZO \
    -fs HFS+ \
    "$DMG" >/dev/null
rm -rf "$DMG_STAGE"
# Sign the DMG itself so Gatekeeper doesn't show a translocation warning.
codesign --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$DMG"
# Notarize and staple the DMG too (separate submission).
xcrun notarytool submit "$DMG" \
  --keychain-profile "$AC_KEYCHAIN_PROFILE" --wait >/dev/null
xcrun stapler staple "$DMG"

echo
echo "Done."
echo "  app: $DIST/Scrobblr.app"
echo "  zip: $ZIP        (for Sparkle updates)"
echo "  dmg: $DMG        (for first-time installs)"
spctl --assess --verbose=2 "$DIST/Scrobblr.app" || true
spctl --assess --type install --verbose=2 "$DMG" || true
