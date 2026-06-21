#!/bin/bash
#
# Build Glide.app from the Swift package, assemble a proper .app bundle, ad-hoc
# sign it with a stable identifier (so the Accessibility grant persists across
# rebuilds), and optionally install to /Applications and launch.
#
#   ./build.sh                 # build + bundle + sign into ./build/Glide.app
#   ./build.sh --install       # also copy to /Applications (or ~/Applications)
#   ./build.sh --install --run # ...and launch it
#
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Glide"
BUNDLE_ID="com.harishankar.glide"
CONFIG="release"

DO_INSTALL=0
DO_RUN=0
for arg in "$@"; do
  case "$arg" in
    --install) DO_INSTALL=1 ;;
    --run)     DO_RUN=1 ;;
  esac
done

echo "Compiling ($CONFIG)..."
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP_DIR="build/${APP_NAME}.app"

echo "Assembling ${APP_DIR}..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

SIGN_IDENTITY="Glide Local Signing"
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  echo "Signing with stable identity ($SIGN_IDENTITY)..."
  codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP_DIR"
else
  echo "Stable identity not found — ad-hoc signing (grant will not persist across rebuilds)..."
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_DIR"
fi
codesign --verify --verbose "$APP_DIR" || true

TARGET="$APP_DIR"
if [[ "$DO_INSTALL" -eq 1 ]]; then
  DEST="/Applications"
  if [[ ! -w "$DEST" ]]; then DEST="$HOME/Applications"; mkdir -p "$DEST"; fi
  echo "Installing to ${DEST}..."
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.5
  rm -rf "$DEST/${APP_NAME}.app"
  cp -R "$APP_DIR" "$DEST/${APP_NAME}.app"
  TARGET="$DEST/${APP_NAME}.app"
  echo "Installed at $TARGET"
fi

if [[ "$DO_RUN" -eq 1 ]]; then
  echo "Launching $TARGET..."
  open "$TARGET"
fi

echo "Done."
