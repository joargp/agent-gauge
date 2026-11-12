#!/usr/bin/env bash
set -euo pipefail

# Wraps a built app in a disk image whose window shows the app, an arrow and
# the Applications folder, so installing is one drag.
#
#   script/make_dmg.sh "dist/Agent Gauge.app" dist/AgentGauge.dmg
#
# Signs the image when AGENT_GAUGE_SIGN_IDENTITY is a Developer ID identity.
# Needs Node (npx) for appdmg, which lays out the window without Finder.

APP="${1:?Path to Agent Gauge.app}"
DMG="${2:?Output .dmg path}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGN_IDENTITY="${AGENT_GAUGE_SIGN_IDENTITY:--}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
APP_ABS="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
VOLUME_ICON="$APP_ABS/Contents/Resources/AppIcon.icns"

# appdmg reads the @2x background next to background.png by itself.
python3 -I - "$WORK/spec.json" "$ROOT_DIR/Resources/dmg/background.png" "$APP_ABS" "$VOLUME_ICON" <<'PY'
import json, os, sys
out, background, app, icon = sys.argv[1:]
spec = {
    "title": "Agent Gauge",
    "background": background,
    "icon-size": 128,
    "window": {"position": {"x": 400, "y": 200}, "size": {"width": 640, "height": 400}},
    "format": "ULFO",
    "contents": [
        {"x": 180, "y": 180, "type": "file", "path": app},
        {"x": 460, "y": 180, "type": "link", "path": "/Applications"},
    ],
}
if os.path.exists(icon):
    spec["icon"] = icon
json.dump(spec, open(out, "w"), indent=2)
PY

rm -f "$DMG"
npx --yes appdmg@0.6.6 "$WORK/spec.json" "$DMG" >&2

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi
echo "$DMG"
