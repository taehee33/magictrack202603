# GitHub Releases 배포 가이드 (Developer ID 없이)

`Developer ID Application` 인증서와 공증 없이 GitHub Releases로 배포하는 방법입니다. v1.2.0, v1.3.0을 이 방식으로 배포했습니다.

## 이 방식의 한계

- 사용자가 처음 열 때 "확인되지 않은 개발자" 경고가 나옵니다.
- 사용자가 **시스템 설정 › 개인정보 보호 및 보안 › 그래도 열기**를 눌러야 합니다. macOS 15부터는 우클릭 › 열기로 넘길 수 없습니다.
- 앱을 Apple Development 인증서로 서명하면 서명 정보에 인증서 이름(Apple ID 이메일)이 들어가고, 받은 사람이 `codesign -dvv`로 볼 수 있습니다.

경고 없이 배포하려면 [공증 준비](../../tools/notarization_setup.md)를 참고하세요.

## 1. 버전 올리기

Xcode 빌드 설정 `MARKETING_VERSION`(예: `1.3.0`)과 `CURRENT_PROJECT_VERSION`(예: `5`)을 올립니다. 배포 스크립트는 [tools/version.sh](../../tools/version.sh)로 이 값을 읽습니다.

## 2. 배포 파일 만들기

```bash
zsh tools/package_dmg.sh        # Release 빌드 + zip + dmg
cd dist && shasum -a 256 MagicMagicTrack-*.dmg MagicMagicTrack-*-macOS.zip > SHA256.txt
```

`dist/`에 생기는 파일:

- `MagicMagicTrack-<버전>-<빌드>.dmg`
- `MagicMagicTrack-<버전>-<빌드>-macOS.zip`
- `SHA256.txt`

권한이 다음 업데이트에도 유지되도록 고정 인증서로 서명해 빌드하세요 (README의 '코드 서명' 참고). 임시 서명으로 배포하면 사용자가 업데이트마다 손쉬운 사용 권한을 다시 허용해야 합니다.

## 3. 릴리스 문서 쓰기

- `docs/release/release-notes-v<버전>.md`: 자세한 릴리즈 노트
- `docs/release/github-release-body-v<버전>.md`: GitHub 릴리스 본문

본문에 꼭 넣을 것 ([v1.3.0 본문](../release/github-release-body-v1.3.0.md) 참고):

- 새 기능 · 고친 문제 · 바뀐 점
- 이전 버전에서 업데이트할 때 알아둘 점 (권한을 다시 허용해야 하는지 등)
- 설치 방법과 "확인되지 않은 개발자" 경고 안내 ([설치 가이드](../install/install-guide-ko.md) 링크)
- 필요한 권한, 요구 사항, 알려진 한계
- 첨부 파일 목록

## 4. 커밋 · 태그 · 릴리스

```bash
git tag v1.3.0
git push github main v1.3.0
gh release create v1.3.0 \
  dist/MagicMagicTrack-1.3.0-5.dmg \
  dist/MagicMagicTrack-1.3.0-5-macOS.zip \
  dist/SHA256.txt \
  --repo taehee33/magictrack202603 \
  --title "MagicMagicTrack v1.3.0" \
  --notes-file docs/release/github-release-body-v1.3.0.md
```

## 5. 올린 뒤 확인

- 릴리스가 **Latest**로 표시되는지
- 첨부한 dmg·zip을 받아 `shasum -a 256`이 `SHA256.txt`와 같은지
- 본문의 링크(릴리즈 노트, 설치 가이드)가 열리는지
- 받은 dmg로 설치해서 경고 → 그래도 열기 → 실행까지 되는지
