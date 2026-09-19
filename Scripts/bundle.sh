#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --disable-sandbox
APP="build/Socius.app"
IDENTITY="${CODESIGN_IDENTITY:-Socius Local Development}"
if ! security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    echo "No stable signing identity found. Run bash Scripts/setup-local-signing.sh first."
    exit 1
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Socius "$APP/Contents/MacOS/Socius"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Vendor/Cyclop/LICENSE "$APP/Contents/Resources/Cyclop-LICENSE.txt"
clang -dynamiclib -fobjc-arc -O2 -mmacosx-version-min=15.0 -framework Foundation -o "$APP/Contents/Resources/libcyclopmedia.dylib" Vendor/Cyclop/helper.m
codesign --force --sign "$IDENTITY" "$APP/Contents/Resources/libcyclopmedia.dylib"
codesign --force --sign "$IDENTITY" "$APP"
echo "Built $APP"
