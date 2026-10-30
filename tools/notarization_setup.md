# 공증 준비 (Developer ID)

공증하면 사용자가 처음 열 때 "확인되지 않은 개발자" 경고 없이 바로 열립니다. 서명 정보에도 Apple ID 이메일 대신 이름이 들어갑니다.

## 1. Apple Developer Program 가입

[developer.apple.com/programs](https://developer.apple.com/programs/)에서 가입합니다 (연 99달러). 무료 Apple ID로는 `Developer ID Application` 인증서를 만들 수 없습니다.

## 2. Developer ID Application 인증서

Xcode › Settings › Accounts › 팀 선택 › Manage Certificates › `+` › **Developer ID Application**을 만듭니다.

```bash
security find-identity -v -p codesigning
# "Developer ID Application: 이름 (TEAMID)"가 보이면 준비 완료
```

## 3. notarytool 자격 증명 저장

[account.apple.com](https://account.apple.com)에서 앱 전용 암호를 만든 뒤 한 번만 저장합니다.

```bash
xcrun notarytool store-credentials "MagicTrackNotary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
```

## 4. 서명 · 공증

```bash
export DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)"
export NOTARY_KEYCHAIN_PROFILE="MagicTrackNotary"
zsh tools/sign_and_notarize.sh
```

[sign_and_notarize.sh](sign_and_notarize.sh)가 하는 일:

1. Release 빌드
2. 앱을 Developer ID로 다시 서명 (hardened runtime, 보안 타임스탬프, 엔타이틀먼트)
3. 서명한 앱으로 dmg를 만들고 dmg도 서명
4. 공증 제출 후 dmg와 앱에 공증 티켓 붙이기
5. 티켓이 붙은 앱으로 zip과 `SHA256.txt` 다시 만들기
6. Gatekeeper 확인 (`spctl`)

공증은 dmg 안의 앱도 Developer ID로 서명돼 있어야 통과합니다. 그래서 dmg만 서명하지 않고 앱부터 다시 서명합니다.

## 5. 확인

스크립트 마지막의 `spctl` 결과에 `source=Notarized Developer ID`가 나오면 성공입니다. 공증이 거절되면 로그를 확인합니다.

```bash
xcrun notarytool log <submission-id> --keychain-profile "MagicTrackNotary"
```

## 공증 후 바뀌는 점

- Developer ID로 서명이 바뀌어 macOS가 새 앱으로 봅니다. **공증한 첫 버전에서는 사용자가 손쉬운 사용 권한을 한 번 다시 허용**해야 합니다. 릴리스 본문에 안내하세요.
- 설치 가이드와 README의 경고 안내를 줄일 수 있습니다.
- 비공개 API를 써도 공증은 받을 수 있습니다 (공증은 악성 코드 검사이고, App Store 심사가 아님).
