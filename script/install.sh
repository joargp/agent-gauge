#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Claude Gauge.app"
EXECUTABLE_NAME="ClaudeGauge"
LABEL="com.joar.claudegauge"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USER_NAME="$(id -un)"
USER_HOME="$(dscl . -read "/Users/$USER_NAME" NFSHomeDirectory | awk 'NR == 1 { print $2 }')"
[[ -n "$USER_HOME" ]] || { echo "Could not resolve the current user home directory" >&2; exit 1; }

SOURCE_APP="$ROOT_DIR/dist/$APP_NAME"
INSTALL_DIR="${CLAUDE_GAUGE_INSTALL_DIR:-$USER_HOME/Applications}"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME"
INSTALLED_BINARY="$INSTALLED_APP/Contents/MacOS/$EXECUTABLE_NAME"
LAUNCH_AGENTS_DIR="$USER_HOME/Library/LaunchAgents"
LAUNCH_AGENT="$LAUNCH_AGENTS_DIR/$LABEL.plist"
USER_DOMAIN="gui/$(id -u)"

TEMP_APP="$INSTALL_DIR/.Claude Gauge.app.new.$$"
BACKUP_APP="$INSTALL_DIR/.Claude Gauge.app.previous.$$"
TEMP_AGENT="$LAUNCH_AGENT.new.$$"
BACKUP_AGENT="$LAUNCH_AGENT.previous.$$"
APP_BACKED_UP=0
AGENT_BACKED_UP=0
NEW_APP_INSTALLED=0
NEW_AGENT_INSTALLED=0
ROLLBACK_ACTIVE=0

xml_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

find_binary_pid() {
  local expected_path="$1"
  local pid
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    if [[ "$(ps -p "$pid" -o comm= 2>/dev/null || true)" == "$expected_path" ]]; then
      printf '%s\n' "$pid"
      return 0
    fi
  done < <(pgrep -x "$EXECUTABLE_NAME" 2>/dev/null || true)
  return 1
}

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

job_is_loaded() {
  launchctl print "$USER_DOMAIN/$LABEL" >/dev/null 2>&1
}

bootout_job() {
  if ! job_is_loaded; then
    return 0
  fi
  launchctl bootout "$USER_DOMAIN/$LABEL"
  for _ in {1..20}; do
    if ! job_is_loaded; then
      return 0
    fi
    sleep 0.05
  done
  echo "Launch agent $LABEL is still loaded after bootout" >&2
  return 1
}

cleanup_temporary_files() {
  rm -rf "$TEMP_APP" "$TEMP_AGENT"
}

rollback_install() {
  set +e
  if ! bootout_job; then
    echo "Rollback stopped before deleting files because the launch agent could not be unloaded." >&2
    cleanup_temporary_files
    set -e
    return
  fi
  if [[ "$NEW_APP_INSTALLED" -eq 1 ]]; then
    stop_binary "$INSTALLED_BINARY"
    rm -rf "$INSTALLED_APP"
  fi
  if [[ "$NEW_AGENT_INSTALLED" -eq 1 ]]; then
    rm -f "$LAUNCH_AGENT"
  fi

  if [[ "$APP_BACKED_UP" -eq 1 && -e "$BACKUP_APP" ]]; then
    mv "$BACKUP_APP" "$INSTALLED_APP"
  fi
  if [[ "$AGENT_BACKED_UP" -eq 1 && -e "$BACKUP_AGENT" ]]; then
    mv "$BACKUP_AGENT" "$LAUNCH_AGENT"
  fi
  if [[ -e "$LAUNCH_AGENT" ]]; then
    launchctl bootstrap "$USER_DOMAIN" "$LAUNCH_AGENT" >/dev/null 2>&1 || true
  fi
  cleanup_temporary_files
  set -e
}

on_exit() {
  local status=$?
  trap - EXIT
  if [[ "$status" -ne 0 && "$ROLLBACK_ACTIVE" -eq 1 ]]; then
    echo "Installation failed; restoring the previous app and launch agent." >&2
    rollback_install
  else
    cleanup_temporary_files
  fi
  exit "$status"
}
trap on_exit EXIT

# Build first. No installed files or user settings are touched here.
CLAUDE_GAUGE_BUILD_CONFIGURATION=release "$ROOT_DIR/script/build_and_run.sh" --stage
CAPTURE_BINARY="$(cd "$ROOT_DIR" && swift build --configuration release --show-bin-path)/claude-gauge-capture"

# Prepare and validate complete replacement artifacts before touching any
# existing installation.
mkdir -p "$INSTALL_DIR" "$LAUNCH_AGENTS_DIR"
rm -rf "$TEMP_APP"
ditto "$SOURCE_APP" "$TEMP_APP"

INSTALLED_APP_XML="$(printf '%s' "$INSTALLED_APP" | xml_escape)"
cat >"$TEMP_AGENT" <<PLIST
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
    <string>$INSTALLED_APP_XML</string>
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
plutil -lint "$TEMP_AGENT" >/dev/null

# From this point, any failure restores the previous app and launch agent.
ROLLBACK_ACTIVE=1
stop_binary "$INSTALLED_BINARY"
bootout_job

if [[ -e "$INSTALLED_APP" ]]; then
  mv "$INSTALLED_APP" "$BACKUP_APP"
  APP_BACKED_UP=1
fi
if [[ -e "$LAUNCH_AGENT" ]]; then
  mv "$LAUNCH_AGENT" "$BACKUP_AGENT"
  AGENT_BACKED_UP=1
fi

mv "$TEMP_APP" "$INSTALLED_APP"
NEW_APP_INSTALLED=1
mv "$TEMP_AGENT" "$LAUNCH_AGENT"
NEW_AGENT_INSTALLED=1
launchctl bootstrap "$USER_DOMAIN" "$LAUNCH_AGENT"

started_pid=""
for _ in {1..30}; do
  if started_pid="$(find_binary_pid "$INSTALLED_BINARY")"; then
    break
  fi
  sleep 0.1
done
if [[ -z "$started_pid" ]]; then
  echo "Launch agent installed, but $EXECUTABLE_NAME did not start from $INSTALLED_APP" >&2
  exit 1
fi

# Settings mutation is last. There are no fallible installation steps after a
# successful registration. Unreadable, empty, malformed, or foreign settings
# fail closed and trigger restoration of the prior app installation.
"$CAPTURE_BINARY" install-statusline

ROLLBACK_ACTIVE=0
rm -rf "$BACKUP_APP" "$BACKUP_AGENT" || true

echo "$APP_NAME installed at $INSTALLED_APP (pid $started_pid)"
echo "Launch at login enabled via $LAUNCH_AGENT"
echo "Restart or start a Claude Code session and send a message to capture fresh usage."
