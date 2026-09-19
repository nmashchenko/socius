#!/bin/bash
set -euo pipefail
FILE="${1:?Usage: notarize.sh FILE [STAPLE_TARGET]}"
TARGET="${2:-$FILE}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool Keychain profile}"
LOG="${FILE}.notary.json"
xcrun notarytool submit "$FILE" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 20m --output-format json > "$LOG"
STATUS=$(plutil -extract status raw -o - "$LOG")
if [ "$STATUS" != Accepted ]; then
    echo "Notarization did not succeed. See $LOG."
    exit 1
fi
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
