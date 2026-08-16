# Codex Account Switcher

A local macOS menu bar companion that switches between user-owned ChatGPT/Codex accounts while preserving the official app, local projects, and Codex task history.

> 개인용 비공식 도구입니다. OpenAI의 공식 ChatGPT/Codex 앱을 대체하거나 수정하지 않습니다.

## 주요 기능

- 공식 Codex App Server 로그인 흐름으로 계정 두 개 등록
- AES-GCM 암호화 프로필과 macOS Keychain 256비트 키
- 사용자 승인형 CLI 종료 후 원자적 인증 전환
- 공식 앱 정상 종료·재실행
- 세션·히스토리·설정·skills 보호 스냅샷과 실패 시 자동 롤백
- 공식 App Server 기반 사용량·초기화 시각 표시
- 같은 task의 대화 맥락과 후속 작업 연속성 검증

## 빠른 시작

요구 사항은 macOS 15 이상, Apple Silicon, Swift 6 도구체인입니다.

```bash
./scripts/test.sh
./scripts/build.sh
./scripts/install.sh
open "$HOME/Applications/Codex Account Switcher.app"
```

로컬 ad-hoc 서명 빌드는 최초 Keychain 승인을 요구할 수 있습니다. 같은 설치본에서 반복 승인을 피하려면 첫 창에서 `항상 허용`을 선택하세요.

## 문서

- [전체 한국어 사용 설명서](README_KO.md)
- [보안 정책](SECURITY.md)
- [아키텍처](docs/ARCHITECTURE.md)
- [공개 환경 검증 결과](docs/ENVIRONMENT_REPORT.md)
- [세션 연속성 검증](docs/SESSION_CONTINUITY_REPORT.md)
- [문제 해결](docs/TROUBLESHOOTING.md)

인증 원문, 브라우저 쿠키, MFA 코드와 비공개 Keychain 항목은 읽거나 저장하지 않습니다.
