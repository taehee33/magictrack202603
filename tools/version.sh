# 버전은 Xcode 빌드 설정(MARKETING_VERSION, CURRENT_PROJECT_VERSION)에 한 곳만 둔다.
# 배포 스크립트에서 source 해서 VERSION, BUILD를 얻는다 (ROOT_DIR이 먼저 정해져 있어야 함)
_build_settings=$(xcodebuild -project "$ROOT_DIR/MagicTrack.xcodeproj" -scheme MagicTrack -configuration Release -showBuildSettings 2>/dev/null)
VERSION=$(print -r -- "$_build_settings" | awk -F' = ' '/^ *MARKETING_VERSION = /{ print $2; exit }')
BUILD=$(print -r -- "$_build_settings" | awk -F' = ' '/^ *CURRENT_PROJECT_VERSION = /{ print $2; exit }')
unset _build_settings

if [[ -z "$VERSION" || -z "$BUILD" ]]; then
  echo "빌드 설정에서 버전을 읽지 못했어요 (MARKETING_VERSION / CURRENT_PROJECT_VERSION)" >&2
  exit 1
fi
