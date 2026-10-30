# 공개 배포 체크리스트

MagicMagicTrack을 GitHub 저장소와 Releases에 올리기 전에 확인할 항목입니다. 배포 절차는 [GitHub Releases 배포 가이드](github-releases-without-developer-id.md)를 보세요.

## 1. 저장소에 개인 정보가 없는지

- 개인 이메일, Apple ID
- Apple Team ID, 인증서 이름 전체 문자열
- 앱 전용 비밀번호, 공증 프로필 이름
- 로컬 절대 경로 (`/Users/...`)
- 이름·메일이 보이는 스크린샷

팀 ID는 `Config/Signing.local.xcconfig`에만 두세요. 이 파일은 git에 올라가지 않습니다.

```bash
git grep -n -I -E "@[a-z0-9.-]+\.[a-z]{2,}|/Users/|Developer ID Application:|Apple Development:|DEVELOPMENT_TEAM = [A-Z0-9]{10}"
```

결과는 후보일 뿐이라 하나씩 읽고 판단합니다. `YOUR_TEAM_ID` 같은 자리 표시는 괜찮습니다.

올리면 안 되는 파일: `.p12`, `.cer`, `.mobileprovision`, `Config/Signing.local.xcconfig`, `dist/`

## 2. 배포 파일

- 앱 이름·아이콘·버전(정보 섹션)이 맞는지
- 설정 탭 › 언어에서 한국어 / English 모두 화면이 깨지지 않는지
- 고정 인증서로 서명했는지 (`codesign -dvv` 의 `Authority`, `TeamIdentifier`)
- Apple Development 인증서로 서명하면 인증서 이름(이메일)이 앱에 들어간다는 점을 알고 있는지
- `zsh Tests/run_tests.sh`가 통과하는지

## 3. 문서

- [README.md](../../README.md), [README.en.md](../../README.en.md): 기능·요구 사항·권한·한계가 이번 버전과 맞는지, 릴리즈 노트 링크 추가
- [설치 가이드](../install/install-guide-ko.md) / [영어](../install/install-guide-en.md): 화면 이름과 경고 안내가 지금 macOS와 맞는지
- `docs/release/release-notes-v<버전>.md`, `docs/release/github-release-body-v<버전>.md`
- [문서 목록](../README.md)에 새 릴리즈 노트 추가

## 4. 릴리스 본문에 꼭 넣을 것

- "확인되지 않은 개발자" 경고가 나오는 이유와 **그래도 열기** 안내
- 필요한 권한 (90° 회전에만 손쉬운 사용)
- 이전 버전에서 업데이트할 때 권한을 다시 허용해야 하는지
- 알려진 한계

## 5. 올린 뒤

- 릴리스가 Latest인지, 첨부 파일 체크섬이 맞는지
- 받은 dmg로 새로 설치해서 실행되는지
- 앱의 '새 버전 확인'이 새 릴리스를 찾는지
