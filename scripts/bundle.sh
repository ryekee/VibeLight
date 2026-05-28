#!/usr/bin/env bash
# bundle.sh — wrap the vibelight-app executable into a runnable VibeLight.app.
# Produces ./build/VibeLight.app. Unsigned; for development use only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG=${CONFIG:-release}
APP_NAME="VibeLight"
APP_DIR="build/${APP_NAME}.app"
BIN_NAME="vibelight-app"
PLIST_SRC="Sources/vibelight-app/AppInfo.plist"

echo "==> Building (${CONFIG})"
swift build -c "$CONFIG"

BIN_PATH=$(swift build -c "$CONFIG" --show-bin-path)/$BIN_NAME
if [ ! -x "$BIN_PATH" ]; then
  echo "ERROR: built binary not found at $BIN_PATH"
  exit 1
fi

if [ ! -f "$PLIST_SRC" ]; then
  echo "ERROR: AppInfo.plist not found at $PLIST_SRC"
  exit 1
fi

echo "==> Creating bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$PLIST_SRC" "$APP_DIR/Contents/Info.plist"

# Patch CFBundleExecutable to match the renamed binary
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$APP_DIR/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" "$APP_DIR/Contents/Info.plist"

echo "==> Done: $APP_DIR"
echo "Launch: open $APP_DIR"
