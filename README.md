# Codex Account Switcher

[![macOS CI](https://github.com/wowhit11-source/codex-account-switcher/actions/workflows/ci.yml/badge.svg)](https://github.com/wowhit11-source/codex-account-switcher/actions/workflows/ci.yml)

A local macOS menu bar companion that switches between user-owned ChatGPT/Codex accounts while preserving the official app, local projects, and Codex task history.

> **비공식 개인용 도구입니다.** 이 프로젝트는 OpenAI와 제휴·후원·승인 관계가 없으며 공식 ChatGPT/Codex 앱을 대체하거나 수정하지 않습니다. 본인이 소유하거나 정당하게 관리 권한을 가진 계정에만 사용하세요. 계정·인증정보 공유, 자동 계정 순환, 동시 다계정 실행 또는 서비스 사용량·요금제 제한 회피 목적의 사용을 지원하거나 권장하지 않습니다. OpenAI, ChatGPT, Codex 명칭은 호환 대상 식별을 위해서만 사용됩니다.

> **지원 환경:** macOS 15 이상이 설치된 **Apple Silicon(arm64) Mac 전용**입니다. 현재 빌드와 실환경 검증은 Apple Silicon에서만 완료했으며 Intel Mac(x86_64)은 지원하거나 검증하지 않았습니다.

## 주요 기능

- 공식 Codex App Server 로그인 흐름으로 여러 계정 등록·변경
- AES-GCM 암호화 프로필과 macOS Keychain 256비트 키
- 사용자 승인형 CLI 종료 후 원자적 인증 전환
- 파일 기반 인증 runtime preflight와 keyring/host-managed 원클릭 차단
- host-managed 공식 앱의 실제 로그아웃 메뉴 실행과 대상 계정 로그인 안내
- 공식 앱 정상 종료·재실행
- 인증 교체 구간 무변경 검사, 세션 보호 스냅샷과 coordinator 자동 롤백
- 공식 App Server 기반 사용량·초기화 시각 표시
- 같은 task의 대화 맥락과 후속 작업 연속성 검증

## 빠른 시작

요구 사항은 macOS 15 이상이 설치된 Apple Silicon(arm64) Mac과 Swift 6 도구체인입니다.

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
- [MIT 라이선스](LICENSE)

인증 원문, 브라우저 쿠키, MFA 코드와 비공개 Keychain 항목은 읽거나 저장하지 않습니다.

> **중요:** 공식 데스크톱 앱이 `features.code_mode_host=true`로 호스트 관리 인증을 사용하는 버전에서는 `auth.json` 교체가 공식 앱 계정을 바꾸지 않습니다. 이 경우 프로필의 `공식 로그인`은 공식 앱의 로그아웃 메뉴를 실행하고 로그인 화면으로 이동합니다. 대상 계정 로그인과 MFA는 사용자가 공식 화면에서 완료해야 합니다.
