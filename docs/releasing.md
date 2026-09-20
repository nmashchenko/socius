# Preparing a release

Release metadata lives in `Scripts/release-version`. Public builds target Apple Silicon and macOS 15+. Local development keeps its separate signing identity and app bundle.

Run tests first:

```sh
swift test --disable-sandbox --no-parallel
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

## Cyclop-style automation

`Scripts/release.sh` checks the clean working tree, exact agreement with pushed `main`, an unused tag, authored release notes, successful `build.yml` CI for the commit, and signing secret names. It then pushes the version tag. `.github/workflows/release.yml` tests, imports signing credentials into a temporary Keychain, builds and notarizes the app and DMG, checks Gatekeeper, and creates a **draft prerelease** with notes and checksums. Publish the draft after reviewing it. A manual workflow dispatch uploads artifacts only.

GitHub runners cannot access this Mac’s Keychain. Configure these repository Actions secrets locally (never paste them into source files or chat):

- `DEVELOPER_ID_P12`: base64 of the exported Developer ID certificate **and private key**.
- `DEVELOPER_ID_P12_PASSWORD`: its export password.
- `NOTARY_KEY_P8`: base64 of an App Store Connect notarization API key.
- `NOTARY_KEY_ID`: its key ID.
- `NOTARY_ISSUER_ID`: issuer ID for a team API key; omit for an individual API key.

Local packaging continues to support `NOTARY_PROFILE=socius-notary`; no credential export is necessary for local builds. No secrets are uploaded by these scripts automatically. Secret provisioning and the first hosted run remain setup steps.

Adapted from [Cyclop release.sh](https://github.com/akalikbergenov/cyclop/blob/main/Scripts/release.sh), [release workflow](https://github.com/akalikbergenov/cyclop/blob/main/.github/workflows/release.yml), and its DMG/notarization flow, under the [MIT license retained in this repository](../Vendor/Cyclop/LICENSE). Socius adds its own test suite, a separate beta tag/build number, temporary credential cleanup, and draft-first publication. Unlike Cyclop’s unsigned dry-run fallback, hosted release preparation requires signing credentials even for manual runs.

## Development and release permissions

Development bundles use `app.socius.desktop.development` and display as Socius Dev. Developer ID releases retain `app.socius.desktop`. Do not reuse the production identifier for local certificates: macOS can show an enabled Accessibility switch while rejecting the running app because the stored signing requirement belongs to another copy.

For a machine affected by older development builds, first replace those builds with the separate development identity. Quit Socius, run `tccutil reset Accessibility app.socius.desktop`, and reopen `/Applications/Socius.app`. Request window control and enable the installed app once. This scoped reset affects only Socius's Accessibility grant; it is a manual repair, never an automatic app-startup action.
