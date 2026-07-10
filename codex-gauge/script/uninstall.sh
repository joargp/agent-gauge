#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Codex Gauge.app"
EXECUTABLE_NAME="CodexGauge"
LABEL="com.joar.codexgauge"
INSTALL_DIR="${CODEX_GAUGE_INSTALL_DIR:-$HOME/Applications}"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
USER_DOMAIN="gui/$(id -u)"

launchctl bootout "$USER_DOMAIN/$LABEL" >/dev/null 2>&1 || true
rm -f "$LAUNCH_AGENT"
pkill -x "$EXECUTABLE_NAME" >/dev/null 2>&1 || true
rm -rf "$INSTALL_DIR/$APP_NAME"

echo "Codex Gauge removed and launch-at-login disabled"
