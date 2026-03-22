# MagicTrack

MagicTrack는 맥북 내장 트랙패드와 블루투스 매직 트랙패드의 설정값을 분리 저장하고, 사용자가 원하는 시점에 해당 설정을 빠르게 적용할 수 있게 만든 macOS 앱입니다.

현재 버전은 Apple 트랙패드 입력 경로의 플랫폼 제약을 고려해, `완전한 실시간 자동 감지`보다는 `수동 전환과 명시적 적용`을 중심으로 설계되어 있습니다.

## 핵심 기능

- 내장 트랙패드 / 매직 트랙패드 설정 분리 저장
- 이동 속도 / 스크롤 속도 / 클릭 압력 개별 조정
- 각 장치 설정을 수동으로 즉시 적용
- 프리셋 저장 / 불러오기
- 앱 자동전환 규칙 설정
- 전역 단축키 `option + M`으로 내장/매직 빠른 전환
- 실행 중 Dock 표시 / 메뉴바 표시 토글

## 현재 지원 상태

- `지원`
  - 장치 연결 감지
  - 내장/매직 트랙패드 구분
  - 장치별 설정 저장
  - 수동 적용
  - 프리셋 저장/적용
  - 앱 자동전환 규칙 관리
  - Dock / 메뉴바 표시 설정

- `실험 또는 제한 사항`
  - 매직 트랙패드 회전 설정
  - Apple 트랙패드의 실입력 감지
  - 좌표/제스처 감지
  - 입력 기반 자동화
  - Apple 트랙패드의 완전한 실시간 독립 이동 속도 제어

위 항목은 UI에서 보일 수 있지만, 현재 버전에서 실제 동작이 완전히 보장되는 기능은 아닙니다.

## 설치

배포 파일과 설치 방법은 아래 문서를 참고하세요.

- [인증서 없이 GitHub Releases로 배포하는 방법](docs/publish/github-releases-without-developer-id.md)
- [사용자 설치 가이드 (한국어)](docs/install/install-guide-ko.md)
- [User Installation Guide (English)](docs/install/install-guide-en.md)
- [릴리즈 노트 v1.1.0](docs/release/release-notes-v1.1.0.md)
- [GitHub Release 본문 템플릿](docs/release/github-release-template-v1.1.0.md)
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
open /tmp/MagicTrackDerivedData/Build/Products/Debug/MagicTrack.app
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

앱의 일부 기능은 macOS 권한이 필요합니다.

- 입력 모니터링: 트랙패드 설정 변경 관련
- 손쉬운 사용: 앱 자동전환 관련

처음 실행 후 권한 안내에 따라 허용해야 정상 동작합니다.
