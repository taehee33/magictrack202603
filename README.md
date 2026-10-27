# MagicMagicTrack

MagicMagicTrack은 맥북 내장 트랙패드와 블루투스 매직 트랙패드의 설정값을 분리 저장하고, 손가락이 닿은 트랙패드의 설정을 바로 적용하는 macOS 앱입니다.

## 핵심 기능

- 내장 트랙패드 / 매직 트랙패드 설정 분리 저장
- 이동 속도 / 스크롤 속도 / 클릭 압력 개별 조정 (시스템 설정과 같은 칸)
- 만진 트랙패드로 자동 전환, 또는 내장 / 매직 고정
- 전역 단축키(기본 `control + option + M`)로 전환 모드 순환 (자동 → 내장 고정 → 매직 고정). 설정 탭에서 바꾸거나 끌 수 있음
- 항목별 되돌리기: 내 기본값 / Mac 기본값
- 프리셋 저장 / 불러오기, 앱 자동전환 규칙
- 매직 트랙패드 회전 (180°, 왼쪽·오른쪽 90°)
- 실행 중 Dock 표시 / 메뉴바 표시 토글

앱이 켜져 있는 동안에만 앱의 설정이 적용되고, 앱을 끄면 시스템 설정 값으로 돌아갑니다. 시스템 설정에 저장된 값은 바꾸지 않습니다.

## 알려진 한계

- 비공개 macOS 기능(MultitouchSupport, 시스템 설정 백엔드, 이벤트 비공개 필드)을 사용합니다. macOS 업데이트 후 자동 전환을 쓸 수 없으면 고정 모드로 동작합니다.
- 90° 회전은 포인터·클릭·드래그·스크롤만 회전되고, 스와이프·핀치 같은 제스처는 회전되지 않습니다.

자세한 내용은 [릴리즈 노트 v1.2.0](docs/release/release-notes-v1.2.0.md)을 참고하세요.

## 설치

배포 파일과 설치 방법은 아래 문서를 참고하세요.

- [인증서 없이 GitHub Releases로 배포하는 방법](docs/publish/github-releases-without-developer-id.md)
- [사용자 설치 가이드 (한국어)](docs/install/install-guide-ko.md)
- [User Installation Guide (English)](docs/install/install-guide-en.md)
- [릴리즈 노트 v1.2.0](docs/release/release-notes-v1.2.0.md)
- [릴리즈 노트 v1.1.0](docs/release/release-notes-v1.1.0.md)
- [GitHub Release 본문 템플릿](docs/release/github-release-template-v1.1.0.md)
- [GitHub Release 최종 본문](docs/release/github-release-body-v1.1.0.md)
- [배포 후 사용자 공지문](docs/release/public-announcement-v1.1.0.md)
- [공개 배포 체크리스트](docs/publish/public-release-checklist.md)

## 로컬 빌드

```bash
xcodebuild -project MagicTrack.xcodeproj \
  -scheme MagicTrack \
  -configuration Debug \
  -derivedDataPath /tmp/MagicTrackDerivedData \
  clean build
```

실행:

```bash
open /tmp/MagicTrackDerivedData/Build/Products/Debug/MagicMagicTrack.app
```

## 배포 파일 생성

Release zip:

```bash
zsh tools/package_release.sh
```

DMG:

```bash
zsh tools/package_dmg.sh
```

서명 및 notarization 준비:

- [notarization_setup.md](tools/notarization_setup.md)

## 권한 안내

기본 기능은 추가 권한 없이 동작합니다. 감도·스크롤·클릭 압력 적용, 만진 트랙패드로 자동 전환, 앱 자동전환, 180° 회전에는 권한이 필요하지 않습니다.

- 손쉬운 사용: 매직 트랙패드를 왼쪽·오른쪽 90°로 회전할 때만 필요합니다. 메인 창 설정 탭의 권한 항목에서 열 수 있습니다.
