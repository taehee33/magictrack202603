#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
INFO_PLIST="$ROOT_DIR/MagicTrack/Resources/Info.plist"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")
APP_NAME="MagicTrack"
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}-${BUILD}.dmg"

: "${DEVELOPER_ID_APP:?Set DEVELOPER_ID_APP to your Developer ID Application certificate name}"
: "${NOTARY_KEYCHAIN_PROFILE:?Set NOTARY_KEYCHAIN_PROFILE to your notarytool keychain profile name}"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "Missing DMG at $DMG_PATH"
  echo "Run ./tools/package_dmg.sh first."
  exit 1
fi

codesign --force --deep --options runtime --sign "$DEVELOPER_ID_APP" "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"

echo "Notarized DMG: $DMG_PATH"
