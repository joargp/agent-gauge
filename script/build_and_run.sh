#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
EXECUTABLE_NAME="AgentGauge"
DISPLAY_NAME="Agent Gauge"
BUNDLE_ID="${AGENT_GAUGE_BUNDLE_ID:-com.joar.agentgauge}"
MIN_SYSTEM_VERSION="14.0"
BUILD_CONFIGURATION="${AGENT_GAUGE_BUILD_CONFIGURATION:-debug}"
VERSION="${AGENT_GAUGE_VERSION:-0.1.0}"
if [[ ! "$VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "AGENT_GAUGE_VERSION must look like 1.2.3, got $VERSION" >&2
  exit 2
fi
# Sparkle compares CFBundleVersion, so it must rise with every release. Deriving
# it from the version keeps it in release order: 0.2.0 is 2000, 1.4.12 is 1004012.
BUILD_NUMBER=$(( 10#${BASH_REMATCH[1]} * 1000000 + 10#${BASH_REMATCH[2]} * 1000 + 10#${BASH_REMATCH[3]} ))
# Set AGENT_GAUGE_UNIVERSAL=1 to build for both Apple silicon and Intel.
UNIVERSAL="${AGENT_GAUGE_UNIVERSAL:-0}"
# "-" signs ad hoc. A Developer ID identity also enables the hardened runtime
# that notarization requires.
SIGN_IDENTITY="${AGENT_GAUGE_SIGN_IDENTITY:--}"
# Built-in updates are on only when the Sparkle public key is set (release
# builds). Without it the app has no updater and shows no update controls.
SPARKLE_PUBLIC_KEY="${AGENT_GAUGE_SPARKLE_PUBLIC_KEY:-}"
FEED_URL="${AGENT_GAUGE_FEED_URL:-https://joargp.github.io/agent-gauge/appcast.xml}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$EXECUTABLE_NAME"
APP_HELPERS="$APP_CONTENTS/Helpers"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_RESOURCES="$APP_CONTENTS/Resources"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icon"
SPARKLE_FRAMEWORK="$APP_FRAMEWORKS/Sparkle.framework"
CAPTURE_NAME="claude-gauge-capture"
INFO_PLIST="$APP_CONTENTS/Info.plist"

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

stop_binary "$APP_BINARY"

cd "$ROOT_DIR"
case "$BUILD_CONFIGURATION" in
  debug|release) ;;
  *)
    echo "AGENT_GAUGE_BUILD_CONFIGURATION must be debug or release" >&2
    exit 2
    ;;
esac

BUILD_FLAGS=(--configuration "$BUILD_CONFIGURATION")
if [[ "$UNIVERSAL" == "1" ]]; then
  BUILD_FLAGS+=(--arch arm64 --arch x86_64)
fi

swift build "${BUILD_FLAGS[@]}"
BUILD_BIN_PATH="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_PATH/$EXECUTABLE_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_HELPERS" "$APP_FRAMEWORKS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

# SwiftPM's default build system records the deployment target as the SDK
# version. macOS then treats the app as built for macOS 14 and skips the
# current system look, such as the larger menu bar window corners.
vtool -set-build-version macos "$MIN_SYSTEM_VERSION" "$(xcrun --sdk macosx --show-sdk-version)" \
  -replace -output "$APP_BINARY" "$APP_BINARY"

# Sparkle. ditto keeps the framework's symlinks and permissions. The XPC
# services are only needed by sandboxed apps, and Agent Gauge isn't one.
ditto "$BUILD_BIN_PATH/Sparkle.framework" "$SPARKLE_FRAMEWORK"
rm -rf "$SPARKLE_FRAMEWORK/XPCServices" "$SPARKLE_FRAMEWORK/Versions/B/XPCServices"
if ! otool -l "$APP_BINARY" | grep -q "@executable_path/../Frameworks"; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY"
fi

# App icon. actool (full Xcode 26 or later) compiles the Icon Composer file into
# Assets.car for macOS 26 and AppIcon.icns for older systems. With only the
# command-line tools installed, the app is built without an icon.
ICON_PLIST=""
if xcrun --find actool >/dev/null 2>&1 \
  && xcrun actool "$ICON_SOURCE" --compile "$APP_RESOURCES" --platform macosx \
    --minimum-deployment-target "$MIN_SYSTEM_VERSION" --app-icon AppIcon \
    --output-partial-info-plist "$DIST_DIR/icon-partial.plist" >/dev/null 2>&1 \
  && [[ -f "$APP_RESOURCES/AppIcon.icns" ]]; then
  ICON_PLIST="  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>"
elif [[ "${AGENT_GAUGE_REQUIRE_ICON:-0}" == "1" ]]; then
  echo "error: the app icon couldn't be compiled; release builds need actool from Xcode 26 or later" >&2
  exit 1
else
  echo "warning: actool from Xcode 26 or later is needed for the app icon; building without one" >&2
fi
rm -f "$DIST_DIR/icon-partial.plist"

# The welcome window's Connect button installs this helper as Claude Code's
# status line.
cp "$BUILD_BIN_PATH/$CAPTURE_NAME" "$APP_HELPERS/$CAPTURE_NAME"
chmod +x "$APP_HELPERS/$CAPTURE_NAME"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
$ICON_PLIST
$(if [[ -n "$SPARKLE_PUBLIC_KEY" ]]; then cat <<SPARKLE
  <key>SUFeedURL</key>
  <string>$FEED_URL</string>
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUAutomaticallyUpdate</key>
  <true/>
SPARKLE
fi)
</dict>
</plist>
PLIST

plutil -lint "$INFO_PLIST" >/dev/null
SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  SIGN_FLAGS+=(--options runtime --timestamp)
fi
# Sign nested code from the inside out: Sparkle's helpers, the framework,
# the capture helper, then the bundle that contains them all.
codesign "${SIGN_FLAGS[@]}" "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate" >/dev/null
codesign "${SIGN_FLAGS[@]}" "$SPARKLE_FRAMEWORK/Versions/B/Updater.app" >/dev/null
codesign "${SIGN_FLAGS[@]}" "$SPARKLE_FRAMEWORK" >/dev/null
codesign "${SIGN_FLAGS[@]}" "$APP_HELPERS/$CAPTURE_NAME" >/dev/null
codesign "${SIGN_FLAGS[@]}" "$APP_BUNDLE" >/dev/null

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --stage|stage)
    echo "$DISPLAY_NAME $VERSION staged at $APP_BUNDLE ($BUILD_CONFIGURATION)"
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$EXECUTABLE_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    for _ in {1..20}; do
      if pid="$(find_binary_pid "$APP_BINARY")"; then
        echo "$DISPLAY_NAME is running from $APP_BUNDLE (pid $pid)"
        exit 0
      fi
      sleep 0.1
    done
    echo "$DISPLAY_NAME did not launch from $APP_BUNDLE" >&2
    exit 1
    ;;
  *)
    echo "usage: $0 [run|--stage|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
