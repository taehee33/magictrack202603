#!/bin/zsh
# 앱 아이콘 다시 만들기 (macOS 26+용 AppIcon.icon + macOS 14·15용 AppIcon.appiconset)
# 사용법: zsh tools/generate_app_icon.sh
# 모양을 바꾸려면 tools/icon/make_icon_composer.py를 고친 뒤 이 스크립트를 다시 실행한다
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCE_DIR="$ROOT_DIR/MagicTrack/Resources"
ICON_DOC="$RESOURCE_DIR/AppIcon.icon"
APPICON_DIR="$RESOURCE_DIR/Assets.xcassets/AppIcon.appiconset"
ICTOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
WORK_DIR="$(mktemp -d /tmp/magictrack-icon.XXXXXX)"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# 1. Icon Composer 문서 (macOS 26 이상: Liquid Glass·다크·틴트는 시스템이 적용)
python3 -I "$ROOT_DIR/tools/icon/make_icon_composer.py" "$ICON_DOC"

# 2. 같은 문서를 시스템 렌더러로 그린 1024 이미지
"$ICTOOL" "$ICON_DOC" --export-image --output-file "$WORK_DIR/render.png" \
  --platform macOS --rendition Default --width 1024 --height 1024 --scale 1 >/dev/null

# 3. 예전 macOS 규격(1024 안 824 + 그림자)으로 옮겨 크기별 PNG 생성 (파일 이름은 Contents.json과 같음)
xcrun swiftc -O -o "$WORK_DIR/make_legacy_icons" "$ROOT_DIR/tools/icon/make_legacy_icons.swift"
"$WORK_DIR/make_legacy_icons" "$WORK_DIR/render.png" "$APPICON_DIR"

echo "Updated $ICON_DOC"
echo "Updated $APPICON_DIR"
