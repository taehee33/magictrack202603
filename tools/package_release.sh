#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="/tmp/MagicTrackReleaseDerivedData"
DIST_DIR="$ROOT_DIR/dist"

source "$ROOT_DIR/tools/version.sh"
APP_NAME="MagicMagicTrack"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/${APP_NAME}.app"
ZIP_PATH="$DIST_DIR/${APP_NAME}-${VERSION}-${BUILD}-macOS.zip"

mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH"

xcodebuild \
  -project "$ROOT_DIR/MagicTrack.xcodeproj" \
  -scheme "MagicTrack" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Packaged: $ZIP_PATH"
