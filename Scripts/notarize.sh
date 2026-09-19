#!/bin/bash
set -euo pipefail
FILE="${1:?Usage: notarize.sh FILE [STAPLE_TARGET]}"
TARGET="${2:-$FILE}"
if [ -n "${NOTARY_PROFILE:-}" ]; then
    AUTH=(--keychain-profile "$NOTARY_PROFILE")
elif [ -n "${NOTARY_KEY_PATH:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ]; then
    AUTH=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID")
    if [ -n "${NOTARY_ISSUER_ID:-}" ]; then AUTH+=(--issuer "$NOTARY_ISSUER_ID"); fi
else
    echo "Set NOTARY_PROFILE or App Store Connect API key credentials."; exit 1
fi
LOG="${FILE}.notary.json"
xcrun notarytool submit "$FILE" "${AUTH[@]}" --wait --timeout 20m --output-format json > "$LOG"
STATUS=$(plutil -extract status raw -o - "$LOG")
if [ "$STATUS" != Accepted ]; then
    echo "Notarization did not succeed. See $LOG."
    exit 1
fi
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
