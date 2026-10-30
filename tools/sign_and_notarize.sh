#!/bin/zsh
# Developer ID로 앱과 dmg를 서명하고 공증까지 한다.
# 공증은 dmg 안의 앱도 Developer ID로 서명돼 있어야 통과하므로,
# Release 빌드(Apple Development 또는 임시 서명)를 Developer ID로 다시 서명한 뒤 zip·dmg를 만든다.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="/tmp/MagicTrackReleaseDerivedData"
DIST_DIR="$ROOT_DIR/dist"
ENTITLEMENTS="$ROOT_DIR/MagicTrack/Resources/MagicTrack.entitlements"

source "$ROOT_DIR/tools/version.sh"
APP_NAME="MagicMagicTrack"
BUILT_APP="$DERIVED_DATA_PATH/Build/Products/Release/${APP_NAME}.app"
SIGNED_DIR="$DIST_DIR/signed"
APP_PATH="$SIGNED_DIR/${APP_NAME}.app"
ZIP_PATH="$DIST_DIR/${APP_NAME}-${VERSION}-${BUILD}-macOS.zip"
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}-${BUILD}.dmg"

: "${DEVELOPER_ID_APP:?Set DEVELOPER_ID_APP to your Developer ID Application certificate name}"
: "${NOTARY_KEYCHAIN_PROFILE:?Set NOTARY_KEYCHAIN_PROFILE to your notarytool keychain profile name}"

# 1. Release 빌드
"$ROOT_DIR/tools/package_release.sh" >/dev/null

# 2. 앱을 Developer ID로 다시 서명 (hardened runtime, 보안 타임스탬프는 공증 필수 조건)
rm -rf "$SIGNED_DIR"
mkdir -p "$SIGNED_DIR"
ditto "$BUILT_APP" "$APP_PATH"
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$DEVELOPER_ID_APP" "$APP_PATH"
codesign --verify --strict --verbose=2 "$APP_PATH"

# 3. 서명한 앱으로 dmg를 만들고 dmg도 서명
APP_PATH="$APP_PATH" "$ROOT_DIR/tools/package_dmg.sh"
codesign --force --timestamp --sign "$DEVELOPER_ID_APP" "$DMG_PATH"

# 4. 공증 후 dmg와 앱에 공증 티켓을 붙인다 (dmg 공증에 안의 앱도 포함됨)
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler staple "$APP_PATH"

# 5. 티켓이 붙은 앱으로 zip을 다시 만들고 체크섬 갱신
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
(cd "$DIST_DIR" && shasum -a 256 "${DMG_PATH:t}" "${ZIP_PATH:t}" > SHA256.txt)

# 6. Gatekeeper 확인
spctl -a -vvv -t exec "$APP_PATH"
spctl -a -vvv -t open --context context:primary-signature "$DMG_PATH"

echo "Notarized: $DMG_PATH"
echo "Notarized: $ZIP_PATH"
