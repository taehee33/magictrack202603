#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="/tmp/MagicTrackReleaseDerivedData"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$DIST_DIR/dmg-staging"

source "$ROOT_DIR/tools/version.sh"
APP_NAME="MagicMagicTrack"
# APP_PATH를 넘기면 그 앱으로 dmg만 만든다 (sign_and_notarize.sh가 다시 서명한 앱을 넘김)
APP_PATH="${APP_PATH:-}"
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}-${BUILD}.dmg"

if [[ -z "$APP_PATH" ]]; then
  "$ROOT_DIR/tools/package_release.sh" >/dev/null
  APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/${APP_NAME}.app"
fi

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$STAGING_DIR"

echo "DMG: $DMG_PATH"
