# Security

## 보안 목표

Codex Account Switcher는 공유 Codex 상태를 유지하면서 인증 캐시만 사용자가 선택한 프로필로 바꿉니다. 비밀번호·MFA·쿠키를 취급하지 않고, 공식 로그인 및 App Server만 사용합니다.

## 저장 데이터

| 데이터 | 저장 위치 | 보호 |
|---|---|---|
| 프로필 메타데이터 | `~/Library/Application Support/CodexAccountSwitcher/profiles.json` | 이메일 마스킹, `0600` |
| 프로필 인증 캐시 | `.../Profiles/<UUID>.casprofile` | AES-GCM, `0600` |
| 긴급복구 백업 | `.../Recovery/latest.recovery` | AES-GCM, `0600` |
| 암호화 키 | macOS Keychain | `AfterFirstUnlockThisDeviceOnly` |
| 활성 인증 | `~/.codex/auth.json` | 원자 교체, `0600` |

AES-GCM 키는 256비트 보안 난수로 처음 한 번 생성합니다. 최초 Keychain 조회 후에는 Switcher 프로세스 메모리에서만 재사용하며 앱 종료 시 캐시가 사라집니다. Keychain 읽기·쓰기·삭제 실패 시 작업을 중단하며 파일 기반 키나 평문 fallback은 없습니다.

## 전환 안전장치

- 전역 `fcntl` lock과 프로세스 내부 registry로 동시 전환 방지
- standalone Codex CLI/IDE가 있으면 감지 목록과 종료 승인창 표시
- 사용자 승인 후 `SIGINT`와 `SIGTERM`만 사용하고, 종료되지 않으면 인증 변경 전 중단
- 공식 앱 정상 종료 우선, 15초 후에도 실행 중이면 사용자 승인 전까지 중단
- 교체 전 기존 인증을 암호화 백업
- 임시 파일 `0600` → write → `fsync` → atomic rename → 디렉터리 `fsync`
- JSON credential 구조, 최종 권한, `account/read`, 대상 이메일 검증
- 보호 파일 삭제 또는 앱 재실행·계정 검증 실패 시 자동 롤백
- 호스트 관리 인증에서는 `auth.json` 주입을 차단하고 사용자 확인 후 공식 앱의 표준 로그아웃 메뉴만 실행

## 로그

로그에는 단계, 성공·실패, 안전한 경로, 오류 코드, 앱/CLI 버전, 보호 파일 해시만 허용합니다. `access_token`, `refresh_token`, `id_token`, `authorization`, `bearer`, `sk-`, JWT 모양 문자열과 이메일은 저장 전 redaction합니다. 인증 JSON 원문과 브라우저 로그인 URL은 로그에 남기지 않습니다.

## 명시적으로 하지 않는 일

- 공식 앱 수정·복제·재서명·패치·인젝션
- 비공개 프레임워크 또는 비공개 Keychain 항목 접근
- 브라우저 쿠키·네트워크 트래픽 가로채기
- OAuth endpoint 직접 호출 또는 요청 위조
- 비밀번호·MFA·세션 쿠키 저장
- 자동 계정 순환 또는 동시 다계정 실행
- 세션·프로젝트·워크트리·설정의 계정별 복제

## 자동화 권한

호스트 관리 인증 환경의 `공식 로그인`은 macOS `System Events`를 통해 공식 앱 메뉴의 `Log Out`/`로그아웃` 항목만 실행합니다. 화면 내용, 키 입력, 브라우저 쿠키 또는 다른 앱의 UI는 읽지 않습니다. 최초 실행 시 macOS 자동화 권한을 요청할 수 있으며, 거부되면 로그아웃하지 않고 중단합니다.

## 삭제와 복구

`scripts/uninstall.sh --purge-data`는 이 앱의 Application Support와 전용 Keychain 키만 삭제합니다. `~/.codex`는 삭제하지 않습니다. 긴급복구는 공식 앱을 종료한 상태에서 `scripts/emergency-restore.sh`로 실행합니다.

APFS와 SSD의 copy-on-write/wear-leveling 때문에 파일 덮어쓰기는 물리 소거를 보장하지 않습니다. 앱은 임시 평문 인증의 수명을 최소화하고 best-effort overwrite 후 제거하지만, 이를 포렌식 수준의 secure erase라고 표현하지 않습니다.
