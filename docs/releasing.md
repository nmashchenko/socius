# Preparing a release

Release metadata lives in `Scripts/release-version`. Public builds target Apple Silicon and macOS 15+. Local development keeps its separate signing identity and app bundle.

Run tests first:

```sh
swift test --disable-sandbox
```

Prepare an Apple Developer ID Application certificate in your login Keychain and save notarization credentials with `xcrun notarytool store-credentials`. Never commit signing keys or passwords.

```sh
CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='socius-notary' ./Scripts/release-dmg.sh
```

This creates `build/release/`: the hardened-runtime app, notarization responses, a signed and stapled DMG, and `SHA256SUMS`. It verifies the app and image with Gatekeeper. It does not publish or create Git tags.

If notarization exceeds the 20-minute wait, inspect the saved `.notary.json` submission response and query its ID with `xcrun notarytool info` or `wait`, using the same Keychain profile. Do not repeatedly submit a pending build.

Before publication, smoke-test the installed Developer ID build (onboarding, drag/return, pocket, shortcut, Spotify and permissions), review the release notes, and publish the DMG as a GitHub prerelease. A signing-identity change from a local development build may require granting macOS permissions again.

The app → notarize/staple → DMG → notarize/staple flow follows Cyclop’s release approach and Apple's distribution guidance. See `Vendor/Cyclop/README.md` for source attribution.
