#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Agent Gauge.app"
EXECUTABLE_NAME="AgentGauge"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USER_NAME="$(id -un)"
USER_HOME="$(dscl . -read "/Users/$USER_NAME" NFSHomeDirectory | awk 'NR == 1 { print $2 }')"
[[ -n "$USER_HOME" ]] || { echo "Could not resolve the current user home directory" >&2; exit 1; }

SOURCE_APP="$ROOT_DIR/dist/$APP_NAME"
INSTALL_DIR="${AGENT_GAUGE_INSTALL_DIR:-$USER_HOME/Applications}"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME"
INSTALLED_BINARY="$INSTALLED_APP/Contents/MacOS/$EXECUTABLE_NAME"
USER_DOMAIN="gui/$(id -u)"

TEMP_APP="$INSTALL_DIR/.Agent Gauge.app.new.$$"
BACKUP_APP="$INSTALL_DIR/.Agent Gauge.app.previous.$$"
APP_BACKED_UP=0
NEW_APP_INSTALLED=0
ROLLBACK_ACTIVE=0

# Claude Gauge and Codex Gauge were separate apps before Agent Gauge merged
# them. Each entry: executable name, app bundle name, launch agent label.
LEGACY_APPS=(
  "ClaudeGauge|Claude Gauge.app|com.joar.claudegauge"
  "CodexGauge|Codex Gauge.app|com.joar.codexgauge"
)

find_binary_pid() {
  local executable_name="$1"
  local expected_path="$2"
  local pid
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    if [[ "$(ps -p "$pid" -o comm= 2>/dev/null || true)" == "$expected_path" ]]; then
      printf '%s\n' "$pid"
      return 0
    fi
  done < <(pgrep -x "$executable_name" 2>/dev/null || true)
  return 1
}

stop_binary() {
  local executable_name="$1"
  local expected_path="$2"
  local pid
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    if [[ "$(ps -p "$pid" -o comm= 2>/dev/null || true)" == "$expected_path" ]]; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
  done < <(pgrep -x "$executable_name" 2>/dev/null || true)
}

bootout_job() {
  local label="$1"
  if ! launchctl print "$USER_DOMAIN/$label" >/dev/null 2>&1; then
    return 0
  fi
  launchctl bootout "$USER_DOMAIN/$label"
  for _ in {1..20}; do
    if ! launchctl print "$USER_DOMAIN/$label" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.05
  done
  echo "Launch agent $label is still loaded after bootout" >&2
  return 1
}

retire_legacy_apps() {
  local entry executable_name app_name label legacy_app
  for entry in "${LEGACY_APPS[@]}"; do
    IFS='|' read -r executable_name app_name label <<<"$entry"
    legacy_app="$INSTALL_DIR/$app_name"

    bootout_job "$label"
    rm -f "$USER_HOME/Library/LaunchAgents/$label.plist"
    if [[ -e "$legacy_app" ]]; then
      stop_binary "$executable_name" "$legacy_app/Contents/MacOS/$executable_name"
      rm -rf "$legacy_app"
      echo "Removed legacy $app_name"
    fi
  done
}

rollback_install() {
  set +e
  if [[ "$NEW_APP_INSTALLED" -eq 1 ]]; then
    stop_binary "$EXECUTABLE_NAME" "$INSTALLED_BINARY"
    rm -rf "$INSTALLED_APP"
  fi
  if [[ "$APP_BACKED_UP" -eq 1 && -e "$BACKUP_APP" ]]; then
    mv "$BACKUP_APP" "$INSTALLED_APP"
    /usr/bin/open -n "$INSTALLED_APP" >/dev/null 2>&1
  fi
  rm -rf "$TEMP_APP"
  set -e
}

on_exit() {
  local status=$?
  trap - EXIT
  if [[ "$status" -ne 0 && "$ROLLBACK_ACTIVE" -eq 1 ]]; then
    echo "Installation failed; restoring the previous app." >&2
    rollback_install
  else
    rm -rf "$TEMP_APP"
  fi
  exit "$status"
}
trap on_exit EXIT

# Build first. No installed files or user settings are touched here.
AGENT_GAUGE_BUILD_CONFIGURATION=release "$ROOT_DIR/script/build_and_run.sh" --stage
CAPTURE_BINARY="$(cd "$ROOT_DIR" && swift build --configuration release --show-bin-path)/claude-gauge-capture"

# Prepare a complete replacement before touching any existing installation.
mkdir -p "$INSTALL_DIR"
rm -rf "$TEMP_APP"
ditto "$SOURCE_APP" "$TEMP_APP"

# From this point, any failure restores the previous app.
ROLLBACK_ACTIVE=1
stop_binary "$EXECUTABLE_NAME" "$INSTALLED_BINARY"

if [[ -e "$INSTALLED_APP" ]]; then
  mv "$INSTALLED_APP" "$BACKUP_APP"
  APP_BACKED_UP=1
fi

mv "$TEMP_APP" "$INSTALLED_APP"
NEW_APP_INSTALLED=1

# Settings mutation is the last fallible step. Unreadable, empty, malformed,
# or foreign settings fail closed and trigger restoration of the prior app.
"$CAPTURE_BINARY" install-statusline

ROLLBACK_ACTIVE=0
rm -rf "$BACKUP_APP" || true

retire_legacy_apps

if "$INSTALLED_BINARY" --enable-launch-at-login; then
  launch_message="Launch at login enabled (System Settings → General → Login Items)"
else
  launch_message="Launch at login could not be enabled; turn it on from the gear menu"
fi

/usr/bin/open -n "$INSTALLED_APP"
started_pid=""
for _ in {1..30}; do
  if started_pid="$(find_binary_pid "$EXECUTABLE_NAME" "$INSTALLED_BINARY")"; then
    break
  fi
  sleep 0.1
done
if [[ -z "$started_pid" ]]; then
  echo "$EXECUTABLE_NAME did not start from $INSTALLED_APP" >&2
  exit 1
fi

echo "$APP_NAME installed at $INSTALLED_APP (pid $started_pid)"
echo "$launch_message"
echo "Restart or start a Claude Code session and send a message to capture fresh usage."
