#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Codex Gauge.app"
EXECUTABLE_NAME="CodexGauge"
LABEL="com.joar.codexgauge"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/dist/$APP_NAME"
INSTALL_DIR="${CODEX_GAUGE_INSTALL_DIR:-$HOME/Applications}"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT="$LAUNCH_AGENTS_DIR/$LABEL.plist"
USER_DOMAIN="gui/$(id -u)"

# Build an ad-hoc signed optimized bundle first. This is a local installation,
# not a notarized distribution artifact.
CODEX_GAUGE_BUILD_CONFIGURATION=release "$ROOT_DIR/script/build_and_run.sh" --stage

mkdir -p "$INSTALL_DIR" "$LAUNCH_AGENTS_DIR"
rm -rf "$INSTALLED_APP"
ditto "$SOURCE_APP" "$INSTALLED_APP"

cat >"$LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-n</string>
    <string>$INSTALLED_APP</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>ProcessType</key>
  <string>Interactive</string>
  <key>LimitLoadToSessionType</key>
  <array>
    <string>Aqua</string>
  </array>
</dict>
</plist>
PLIST

plutil -lint "$LAUNCH_AGENT" >/dev/null
launchctl bootout "$USER_DOMAIN/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "$USER_DOMAIN" "$LAUNCH_AGENT"

# RunAtLoad launches it immediately after bootstrap. Give LaunchServices a
# moment before treating an absent process as a failure.
for _ in {1..20}; do
  if pgrep -x "$EXECUTABLE_NAME" >/dev/null; then
    echo "$APP_NAME installed at $INSTALLED_APP"
    echo "Launch at login enabled via $LAUNCH_AGENT"
    exit 0
  fi
  sleep 0.25
done

echo "Launch agent installed, but $EXECUTABLE_NAME did not start" >&2
exit 1
