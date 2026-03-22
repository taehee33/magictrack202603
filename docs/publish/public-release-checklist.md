# 공개 배포 체크리스트

이 문서는 MagicTrack를 공개 Git 저장소와 GitHub Releases에 올리기 전 확인해야 할 항목을 정리한 체크리스트입니다.

## 1. 공개 전 정보 검열

아래 항목이 저장소에 남아 있지 않은지 확인합니다.

- 개인 이메일 주소
- Apple Team ID
- 인증서 이름 전체 문자열
- 로컬 절대 경로
- 다운로드 폴더 경로
- 개인 기기 이름
- 테스트용 임시 계정 정보
- notarization 프로필명 같은 운영 정보

확인 명령 예시:

```bash
rg -n "YOUR_|@|/Users/|Developer ID Application|Apple Development|TEAMID|notarytool|Notary" .
```

주의:

- 위 명령은 후보를 넓게 잡는 용도입니다
- 실제 공개 전에는 각 결과를 직접 읽고 판단해야 합니다

## 2. 공개 저장소에 올려도 되는 것

- 앱 소스 코드
- 일반 빌드 스크립트
- 공개용 문서
- 설치 가이드
- 릴리즈 노트
- 예시용 placeholder 값

예:

- `YOUR_APPLE_ID`
- `YOUR_TEAM_ID`
- `Your Name`

## 3. 공개 저장소에 올리면 안 되는 것

- 실제 Apple ID 메일
- 실제 앱 전용 비밀번호
- 실제 Team ID와 결합된 인증서 정보
- 인증서 파일
- `.p12`
- `.cer`
- 개인 키체인 설정
- 개인 테스트 스크린샷 중 이름/메일이 보이는 것
- 로컬 개발 경로가 적힌 배포 문서

## 4. 문서 점검

확인할 문서:

- `README.md`
- `docs/install-guide-ko.md`
- `docs/install-guide-en.md`
- `docs/github-releases-without-developer-id.md`
- `docs/github-release-template-v1.1.0.md`
- `docs/release-notes-v1.1.0.md`

점검 항목:

- 절대 경로 제거
- 개인 이름/메일 제거
- 실제 인증서 문자열 제거
- 팀 ID 제거
- 로컬 테스트 전용 문구 제거

## 5. 배포 파일 점검

- `.dmg`
- `.zip`
- `README`
- 릴리즈 노트

확인할 것:

- 아이콘이 정상인지
- 앱 이름이 올바른지
- 버전 정보가 맞는지
- 권한 안내가 있는지
- 제한 사항이 정확한지

## 6. GitHub Releases 업로드 전

- 태그명 확인
  - 예: `v1.1.0`
- 제목 확인
  - 예: `MagicTrack v1.1.0`
- 첨부 파일 확인
- 릴리즈 본문 확인
- 설치 가이드 링크 확인

## 7. 인증서 없이 배포할 때 꼭 써야 하는 문구

```text
이 배포본은 아직 Apple Developer ID 서명 및 notarization이 적용되지 않았습니다.
처음 실행 시 macOS 보안 경고가 나타날 수 있습니다.
문제가 발생하면 설치 가이드를 참고해주세요.
```

## 8. 사용자 문의를 줄이기 위한 필수 안내

- 어떤 권한이 필요한지
- 어떤 기능이 실험 기능인지
- 어떤 기능이 현재 미지원인지
- 왜 보안 경고가 뜨는지
- 설치 실패 시 어디서 허용하는지

## 9. 공개 전 최종 확인

- 저장소에 개인 정보 없음
- 문서에 절대 경로 없음
- 빌드 성공
- 설치 테스트 완료
- 릴리즈 본문 준비 완료
- 첨부 파일 준비 완료

## 10. 다음 단계

향후 더 많은 사용자에게 안정적으로 배포하려면:

1. Apple Developer Program 가입
2. Developer ID Application 인증서 발급
3. notarization 적용
4. 서명된 DMG 재배포

