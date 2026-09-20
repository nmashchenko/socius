#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/release-version
swift build -c release --arch arm64 --disable-sandbox
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
APP="${APP_OUTPUT:-build/Socius.app}"
IDENTITY="${CODESIGN_IDENTITY:-Socius Local Development}"
if [ "$IDENTITY" != "-" ] && ! security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    echo "No stable signing identity found. Run bash Scripts/setup-local-signing.sh first."
    exit 1
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Socius" "$APP/Contents/MacOS/Socius"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"
CHANNEL=development
if [[ "$IDENTITY" == "Developer ID Application:"* ]]; then CHANNEL=release; fi
/usr/libexec/PlistBuddy -c "Add :SociusBuildChannel string $CHANNEL" "$APP/Contents/Info.plist"
if [ "$CHANNEL" = development ]; then
    /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier app.socius.desktop.development' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleName Socius Dev' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Socius Dev' "$APP/Contents/Info.plist"
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
cp Vendor/Cyclop/LICENSE "$APP/Contents/Resources/Cyclop-LICENSE.txt"
clang -dynamiclib -fobjc-arc -O2 -mmacosx-version-min=15.0 -framework Foundation -o "$APP/Contents/Resources/libcyclopmedia.dylib" Vendor/Cyclop/helper.m
if [[ "$IDENTITY" == "Developer ID Application:"* ]]; then
    codesign --force --timestamp --sign "$IDENTITY" "$APP/Contents/Resources/libcyclopmedia.dylib"
    codesign --force --timestamp --options runtime --entitlements Resources/Release.entitlements --sign "$IDENTITY" "$APP"
else
    codesign --force --sign "$IDENTITY" "$APP/Contents/Resources/libcyclopmedia.dylib"
    codesign --force --sign "$IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "Built $APP"
