#!/bin/bash
# Adapted from Cyclop's MIT-licensed release preflight; see docs/releasing.md.
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/release-version
fail() { echo "Release stopped: $1" >&2; exit 1; }
command -v gh >/dev/null || fail "Install GitHub CLI first."
gh auth status >/dev/null 2>&1 || fail "Run gh auth login."
[ -z "$(git status --porcelain)" ] || fail "Commit all changes first."
[ "$(git branch --show-current)" = main ] || fail "Release from main."
git fetch --quiet origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "Local main must match origin/main."
! git rev-parse --verify "refs/tags/$RELEASE_TAG" >/dev/null 2>&1 || fail "Tag already exists."
[ -z "$(git ls-remote --tags origin "refs/tags/$RELEASE_TAG")" ] || fail "Remote tag already exists."
[ -s "docs/releases/${RELEASE_TAG#v}.md" ] || fail "Write release notes first."
CI=$(gh run list --commit "$(git rev-parse HEAD)" --workflow build.yml --json conclusion --jq '.[0].conclusion // "none"')
[ "$CI" = success ] || fail "CI is $CI; release requires a successful build."
SECRETS=$(gh secret list --json name --jq '.[].name')
for NAME in DEVELOPER_ID_P12 DEVELOPER_ID_P12_PASSWORD NOTARY_KEY_P8 NOTARY_KEY_ID; do
    printf '%s\n' "$SECRETS" | grep -qx "$NAME" || fail "Missing Actions secret: $NAME (see docs/releasing.md)."
done
echo "Creating $RELEASE_TAG. The workflow prepares a draft GitHub prerelease."
git tag -a "$RELEASE_TAG" -m "Socius ${RELEASE_TAG#v}"
git push origin "$RELEASE_TAG"
echo "Track progress with: gh run watch"
