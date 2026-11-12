#!/usr/bin/env bash
set -euo pipefail

# Publishes a release: checks that main is clean, pushed and green on CI,
# then creates the GitHub release with your notes. Creating the release also
# creates the tag, which starts the Release workflow (build, notarize, upload
# the disk image and zip, and add the version to the update feed).
#
#   script/release.sh 0.1.7 notes.md
#
# notes.md holds short bullet points ("* ..."). The app's "What's new" shows
# the first three; GitHub shows them all.

VERSION="${1:?Usage: script/release.sh VERSION NOTES_FILE}"
NOTES="${2:?Usage: script/release.sh VERSION NOTES_FILE}"
TAG="v$VERSION"

fail() { echo "error: $*" >&2; exit 1; }

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "versions look like 1.2.3, got $VERSION"
[[ -f "$NOTES" ]] || fail "notes file not found: $NOTES"

bullets="$(grep -cE '^\s*[-*]\s+\S' "$NOTES" || true)"
(( bullets > 0 )) || fail "$NOTES has no bullet points; the app's What's new would be empty"
if (( bullets > 3 )); then
  echo "note: $NOTES has $bullets bullet points; the app shows only the first 3" >&2
fi

cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ "$(git branch --show-current)" == "main" ]] || fail "switch to main first"
[[ -z "$(git status --porcelain)" ]] || fail "commit or stash your changes first"
git fetch -q origin main --tags
SHA="$(git rev-parse HEAD)"
[[ "$SHA" == "$(git rev-parse origin/main)" ]] || fail "main isn't the same as origin/main; push or pull first"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  fail "$TAG already exists"
fi

ci="$(gh run list --commit "$SHA" --workflow ci.yml --limit 1 --json status,conclusion --jq '.[0] | "\(.status) \(.conclusion)"')"
[[ "$ci" == "completed success" ]] || fail "CI for ${SHA:0:7} is '${ci:-not started}'; wait for it to pass"

echo "Releasing Agent Gauge $VERSION from ${SHA:0:7} with these notes:"
cat "$NOTES"
read -r -p "Publish? [y/N] " answer
[[ "$answer" == [yY] ]] || fail "cancelled"

gh release create "$TAG" --target "$SHA" --title "Agent Gauge $VERSION" --notes-file "$NOTES"

# The tag push starts the workflow a few seconds later.
for _ in {1..10}; do
  run="$(gh run list --workflow release.yml --branch "$TAG" --limit 1 --json url --jq '.[0].url // empty')"
  [[ -n "$run" ]] && break
  sleep 3
done
echo "Release workflow: ${run:-see the Actions tab}"
echo "It takes 10 to 30 minutes, most of it waiting for Apple's notarization."
echo "Afterwards, update site/index.html (download label, size and Recent changes)."
