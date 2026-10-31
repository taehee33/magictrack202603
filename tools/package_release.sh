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

# 배포본에는 디버거 연결 허용(get-task-allow)을 넣지 않는다
xcodebuild \
  -project "$ROOT_DIR/MagicTrack.xcodeproj" \
  -scheme "MagicTrack" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Packaged: $ZIP_PATH"
