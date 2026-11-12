#!/usr/bin/env bash
set -euo pipefail

# Builds a universal release of Agent Gauge: a zip for the update feed and a
# disk image (AgentGauge.dmg) for the website download.
#
#   AGENT_GAUGE_VERSION        version string, e.g. 0.2.0 (required)
#   AGENT_GAUGE_SIGN_IDENTITY  Developer ID identity; ad hoc when unset
#   NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER_ID
#                              App Store Connect API key for notarization;
#                              skipped unless all three are set
#
# The disk image is written to dist/AgentGauge.dmg. Prints the path of the
# finished zip on the last line.

: "${AGENT_GAUGE_VERSION:?Set AGENT_GAUGE_VERSION}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/Agent Gauge.app"
ZIP_PATH="$ROOT_DIR/dist/AgentGauge-$AGENT_GAUGE_VERSION.zip"
DMG_PATH="$ROOT_DIR/dist/AgentGauge.dmg"

AGENT_GAUGE_BUILD_CONFIGURATION=release AGENT_GAUGE_UNIVERSAL=1 AGENT_GAUGE_REQUIRE_ICON=1 \
  "$ROOT_DIR/script/build_and_run.sh" --stage

codesign --verify --strict --verbose=2 "$APP_BUNDLE"
lipo -info "$APP_BUNDLE/Contents/MacOS/AgentGauge"

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

NOTARIZE=0
if [[ -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]]; then
  NOTARIZE=1
fi
notarize() {
  xcrun notarytool submit "$1" \
    --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" \
    --wait
}

if (( NOTARIZE )); then
  notarize "$ZIP_PATH"
  xcrun stapler staple "$APP_BUNDLE"
  # Re-zip so the download carries the stapled ticket.
  rm -f "$ZIP_PATH"
  ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
  echo "Notarized and stapled the app" >&2
else
  echo "Not notarized: NOTARY_KEY_PATH, NOTARY_KEY_ID and NOTARY_ISSUER_ID are not all set" >&2
fi

# The disk image holds the stapled app and is notarized on its own, so it
# opens without warnings even offline.
"$ROOT_DIR/script/make_dmg.sh" "$APP_BUNDLE" "$DMG_PATH" >&2
if (( NOTARIZE )); then
  notarize "$DMG_PATH"
  xcrun stapler staple "$DMG_PATH"
  echo "Notarized and stapled the disk image" >&2
fi

echo "$ZIP_PATH"
