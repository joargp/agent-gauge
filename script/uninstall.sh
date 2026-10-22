#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Agent Gauge.app"
EXECUTABLE_NAME="AgentGauge"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USER_NAME="$(id -un)"
USER_HOME="$(dscl . -read "/Users/$USER_NAME" NFSHomeDirectory | awk 'NR == 1 { print $2 }')"
[[ -n "$USER_HOME" ]] || { echo "Could not resolve the current user home directory" >&2; exit 1; }

INSTALL_DIR="${AGENT_GAUGE_INSTALL_DIR:-$USER_HOME/Applications}"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME"
INSTALLED_BINARY="$INSTALLED_APP/Contents/MacOS/$EXECUTABLE_NAME"

stop_binary() {
  local expected_path="$1"
  local pid
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    if [[ "$(ps -p "$pid" -o comm= 2>/dev/null || true)" == "$expected_path" ]]; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
  done < <(pgrep -x "$EXECUTABLE_NAME" 2>/dev/null || true)
}

# Always use a freshly built helper from this same trusted source tree. Never
# execute the installed statusline helper, which is a user-writable path and
# may have been replaced or redirected since installation.
cd "$ROOT_DIR"
swift build --configuration release --product claude-gauge-capture
CAPTURE_TOOL="$(swift build --configuration release --show-bin-path)/claude-gauge-capture"

"$CAPTURE_TOOL" uninstall-statusline

if [[ -x "$INSTALLED_BINARY" ]]; then
  "$INSTALLED_BINARY" --disable-launch-at-login || echo "Could not remove the login item; remove Agent Gauge in System Settings → General → Login Items" >&2
fi
stop_binary "$INSTALLED_BINARY"
rm -rf "$INSTALLED_APP"

echo "Agent Gauge removed and launch at login disabled"
