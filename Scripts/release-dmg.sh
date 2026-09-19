#!/bin/bash
# Local release preparation only: never creates tags or publishes to GitHub.
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/release-version
: "${CODESIGN_IDENTITY:?Set CODESIGN_IDENTITY to your Developer ID Application certificate}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your notarytool Keychain profile}"
[[ "$CODESIGN_IDENTITY" == "Developer ID Application:"* ]] || { echo "Developer ID Application signing is required."; exit 1; }
APP="build/release/Socius.app"
DMG="build/release/Socius-${RELEASE_TAG#v}-arm64.dmg"
APP_OUTPUT="$APP" ./Scripts/bundle.sh
ZIP="build/release/Socius-notarization.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
./Scripts/notarize.sh "$ZIP" "$APP"
STAGE=$(mktemp -d "${TMPDIR:-/tmp/}socius-dmg.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Socius.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -ov -volname "Socius $VERSION Beta" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG"
./Scripts/notarize.sh "$DMG"
spctl --assess --type execute --verbose=2 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
(cd build/release && shasum -a 256 "$(basename "$DMG")" > SHA256SUMS)
echo "Ready for review: $DMG"
