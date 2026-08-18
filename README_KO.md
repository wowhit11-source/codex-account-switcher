# Codex Account Switcher

Codex Account Switcher는 macOS 메뉴바에서 **사용자가 직접 선택한 ChatGPT/Codex 계정으로 인증을 전환**하는 로컬 보조 앱입니다. 새로운 Codex 클라이언트가 아니며, 공식 `/Applications/ChatGPT.app`의 하네스·프로젝트·터미널·Diff·샌드박스·승인·워크트리·세션 UI는 전혀 대체하지 않습니다.

공식 앱 번들, 바이너리, 코드 서명, 자동 업데이트 파일은 수정하지 않습니다. 브라우저 쿠키나 공식 앱의 비공개 Keychain 항목도 읽지 않습니다.

> **지원 환경:** macOS 15 이상이 설치된 **Apple Silicon(arm64) Mac 전용**입니다. 현재 빌드와 실환경 검증은 Apple Silicon에서만 완료했으며 Intel Mac(x86_64)은 지원하거나 검증하지 않았습니다.

## 현재 확인 상태

- macOS 15 이상, Apple Silicon 환경에서 빌드 및 자동 테스트 완료
- 공식 앱 `/Applications/ChatGPT.app`, 실제 Bundle Identifier `com.openai.codex` 탐지 완료
- 번들 Codex App Server의 `account/read`, `account/rateLimits/read`, `account/usage/read` 확인 완료
- 현재 설치 환경의 `~/.codex/auth.json` 파일 기반 인증과 권한 `0600` 확인 완료
- 가짜 `CODEX_HOME`에서 인증만 바꾸는 10회 전환, 공유 상태 해시 불변, 실패 복구 확인 완료
- 파일 기반 인증을 사용하던 공식 앱에서 실제 두 계정 전환, 앱 재실행, 동일 task 대화 맥락 유지와 후속 코드 작업 확인 완료
- 전체 자동 테스트 42개 통과

자세한 실환경 결과는 [환경 진단](docs/ENVIRONMENT_REPORT.md)과 [세션 연속성 보고서](docs/SESSION_CONTINUITY_REPORT.md)를 확인하세요.

## 빌드

요구 사항은 macOS 15 이상이 설치된 Apple Silicon(arm64) Mac과 Xcode 26 또는 Swift 6 도구체인입니다. 외부 패키지는 사용하지 않습니다.

```bash
./scripts/test.sh
./scripts/build.sh
```

빌드 결과는 다음 위치에 생성됩니다.

```text
dist/Codex Account Switcher.app
```

`CodexAccountSwitcher.xcodeproj`를 Xcode에서 열고 `Codex Account Switcher` scheme을 Build해도 같은 Release 앱이 생성됩니다. 프로젝트는 Swift Package를 호출하는 Xcode External Build target이므로 명령행과 Xcode가 동일한 산출물을 사용합니다.

## 설치와 실행

```bash
./scripts/install.sh
open "$HOME/Applications/Codex Account Switcher.app"
```

설치 스크립트는 사용자 전용 `~/Applications`만 사용합니다. `/Applications`에는 쓰지 않습니다. 첫 실행 후 메뉴바의 순환 화살표 아이콘을 누르세요.

## 계정 등록

등록 개수 제한 없이 여러 계정을 지원합니다. 계정 목록은 메뉴 안에서 스크롤됩니다.

1. `~/.codex/auth.json`에 저장된 계정을 등록하려면 `저장 인증 등록`을 누릅니다. 공식 앱이 호스트 관리 인증을 사용하면 앱 내부 계정과 이 파일의 계정이 다를 수 있습니다.
2. 앱은 `auth.json`을 검증한 뒤 즉시 AES-GCM으로 암호화합니다.
3. `계정 추가`를 누르면 별도 임시 `CODEX_HOME`에서 공식 App Server의 `account/login/start` 브라우저 흐름을 시작합니다.
4. 브라우저에서 사용자가 직접 추가할 계정의 로그인·MFA를 완료합니다.
5. App Server의 `account/login/completed`와 `account/read`가 성공한 경우에만 프로필로 저장합니다.

브라우저 callback이 불안정하면 `Device Code 추가`를 사용할 수 있습니다. 코드는 클립보드에 복사되고 공식 verification URL이 열립니다. 비밀번호, MFA 코드, 브라우저 쿠키는 앱이 보거나 저장하지 않습니다.

이미 등록된 계정으로 다시 로그인하면 중복 프로필을 만들지 않고 저장된 인증을 갱신합니다. 프로필 오른쪽 `…` 메뉴에서 `브라우저로 계정 변경` 또는 `Device Code로 계정 변경`을 선택하면 프로필 이름은 유지한 채 다른 계정의 인증으로 교체할 수 있습니다. 파일 기반 인증 환경에서는 교체 후 `전환`을 누릅니다. 호스트 관리 인증 환경에서는 저장 프로필을 공식 앱에 주입할 수 없으므로 `공식 로그인`으로 공식 앱을 로그아웃한 뒤 해당 계정으로 로그인해야 합니다.

## 계정 전환

1. 파일 기반 인증 환경에서는 메뉴에서 비활성 프로필의 `전환`을 누릅니다. `keyring`, 호스트 관리 인증, 알 수 없는 저장소 또는 검증되지 않은 `auth.json` 환경에서는 원클릭을 실행하지 않습니다.
2. 경고 내용을 확인하고 사용자가 `전환`을 다시 누릅니다.
3. 별도 Codex CLI·IDE 프로세스가 실행 중이면 감지 목록을 보여주고 `CLI 종료 후 전환` 승인을 요청합니다.
4. 사용자가 승인하면 먼저 `SIGINT`, 남아 있으면 `SIGTERM`으로 정상 종료를 요청합니다. `SIGKILL`은 사용하지 않으며 종료되지 않으면 인증을 건드리기 전에 중단합니다.
5. `cli_auth_credentials_store`, 유효한 `auth.json`, 새 App Server의 실제 계정 응답을 확인합니다. `auto` 또는 미설정도 runtime 확인에 성공해야 합니다.
6. 세션·히스토리·설정·skills의 경로, 크기, 수정 시각, SHA-256 스냅샷을 만듭니다.
7. 현재 인증 캐시를 최신화해 현재 프로필에 다시 암호화 저장합니다.
8. 실제 Bundle Identifier로 공식 앱에 정상 종료를 요청합니다.
9. 정상 종료가 15초 안에 끝나지 않으면 사용자의 별도 승인 없이는 강제 종료하지 않습니다.
10. 기존 인증을 암호화된 긴급복구 백업으로 저장한 뒤 대상 인증을 임시 파일·`fsync`·원자적 rename으로 교체합니다.
11. 권한 `0600`, JSON 구조, `account/read(refreshToken: true)`, 실제 이메일 일치를 검증합니다.
12. 공식 앱이 멈춘 조용한 구간에서 인증 외 보호 상태의 경량 manifest가 하나라도 바뀌면 즉시 롤백합니다.
13. 공식 앱을 원래 설치 경로에서 다시 실행한 뒤 보호 상태를 비교합니다.

실패하면 이전 인증으로 자동 롤백하고 공식 앱을 다시 실행합니다. `history.jsonl`, `sessions`, 설정, skills, rules, hooks, 작업 폴더, Git 저장소, 워크트리는 전환 대상이 아닙니다.

공식 앱이 `features.code_mode_host=true`로 실행되는 현재 버전에서는 호스트가 로그인 토큰 수명주기를 소유하므로 `auth.json`만 교체해 데스크톱 계정을 바꿀 수 없습니다. 이때 각 프로필에는 `공식 로그인`이 표시됩니다. 누르면 사용자 확인 후 macOS 자동화 권한으로 공식 앱의 실제 `로그아웃` 메뉴를 실행하며, 이어서 공식 앱에서 대상 계정의 로그인·MFA를 직접 완료합니다. Codex 데스크톱은 현재 두 계정의 무로그인 즉시 전환을 제공하지 않습니다.

## 사용량 표시

사용량은 공식 App Server의 `account/rateLimits/read`가 반환한 `usedPercent`와 `resetsAt`만 표시합니다. `account/usage/read`가 성공하면 토큰 활동 요약도 내부 상태로 읽습니다. 응답이 없거나 인증 모드가 지원하지 않으면 `사용량 정보 없음`으로 표시하며 추정값을 만들지 않습니다.

## Session Continuity Test

1. `연속성 테스트 시작`을 누릅니다. `CAS-PROBE-<UUID>`가 클립보드에 복사됩니다.
2. 공식 앱에서 테스트용 로컬 프로젝트의 기존 대화에 마커를 붙여넣습니다.
3. 메뉴에서 `마커 찾기`를 눌러 로컬 session 파일과 thread/session ID를 기록합니다.
4. 계정 B로 전환합니다.
5. 같은 세션을 열고 `이 대화 앞부분에 기록된 CAS-PROBE 마커를 정확히 말해줘.`를 입력합니다.
6. 현재 계정을 새로고침해 B가 활성인지 확인합니다.
7. 실제 후속 작업까지 성공했으면 PASS, 로컬 목록만 남고 실행이 거부되거나 새 thread로 갈라지면 PARTIAL, 세션이 사라지거나 열리지 않으면 FAIL을 누릅니다.
8. 계정 A로 돌아가 같은 세션이 손상되지 않았는지 확인합니다.

세션 파일이 존재한다는 사실만으로 PASS 처리하지 마세요. PASS는 계정 B 인증으로 동일 thread/session에서 실제 후속 요청이 성공한 경우뿐입니다.

## 인증 데이터 보관

- 암호화: Apple CryptoKit AES-GCM
- 키: macOS Keychain의 이 앱 전용 generic-password 항목
- 키 캐시: 최초 Keychain 조회 후 Switcher 프로세스 메모리에서만 재사용
- 암호문: `~/Library/Application Support/CodexAccountSwitcher/Profiles/`
- 메타데이터: 표시 이름, 마스킹된 이메일, 플랜, 검증 시각만 저장
- 활성 인증: 공식 Codex가 사용하는 것으로 실환경 확인된 `~/.codex/auth.json`만 원자 교체
- 권한: 디렉터리 `0700`, 인증·암호문·메타데이터 `0600`

Keychain 또는 암호화가 실패하면 평문 fallback 없이 중단합니다. APFS/SSD에서는 덮어쓰기가 물리 블록 소거를 보장하지 않으므로 임시 평문 파일은 가능한 짧게 유지하고, 앱이 연 임시 파일을 best-effort로 덮어쓴 뒤 제거합니다.

로컬 ad-hoc 서명 빌드는 재빌드할 때 Keychain이 새 바이너리로 판단해 최초 승인을 다시 요구할 수 있습니다. 한 설치본에서는 첫 승인창의 `항상 허용`을 선택하면 이후 승인이 생략되며, `허용`만 선택해도 프로세스 키 캐시 덕분에 한 번의 실행 중 반복 승인창은 나타나지 않습니다.

## 필요한 권한

- Keychain: 프로필 암호화 키 저장
- 다른 앱 종료·실행: 공식 `com.openai.codex` 앱의 정상 종료 및 재실행
- 자동화: 호스트 관리 인증에서 공식 앱의 표준 `로그아웃` 메뉴 실행
- 파일 접근: 사용자의 공유 `CODEX_HOME`에서 인증 파일 교체와 보호 상태 읽기
- 로그인 시 실행(선택): 사용자가 설정에서 직접 켠 경우 `SMAppService`

Accessibility와 화면 녹화는 요구하지 않습니다. `공식 로그인`을 처음 누르면 macOS가 `System Events` 자동화 권한을 한 번 요청할 수 있습니다. 브라우저 쿠키와 공식 앱의 비공개 Keychain 항목은 읽지 않습니다.

## 긴급 복구

메뉴의 `긴급 복구`를 누르거나 공식 앱을 먼저 정상 종료한 뒤 다음을 실행합니다.

```bash
./scripts/emergency-restore.sh
```

스크립트는 토큰을 출력하지 않습니다. 설치 앱의 `--emergency-restore` 모드가 Keychain 키로 마지막 백업을 복호화하고 권한 `0600`으로 복원한 뒤 공식 앱을 엽니다.

## 삭제

앱만 제거하고 암호화 프로필을 보존합니다.

```bash
./scripts/uninstall.sh
```

앱, 암호화 프로필, 복구 백업, 전용 Keychain 키를 모두 삭제합니다.

```bash
./scripts/uninstall.sh --purge-data
```

어느 경우에도 `~/.codex`, 기존 세션, 프로젝트, 작업 폴더는 삭제하지 않습니다.

## 현재 환경에서 확인된 한계

- 실제 계정 B 로그인·MFA는 자동화하지 않으며 사용자가 직접 완료해야 합니다.
- standalone CLI가 감지되면 사용자에게 종료 승인을 요청하며, 승인 없이 종료하거나 전환하지 않습니다.
- 공식 데스크톱 호스트가 `chatgptAuthTokens` 같은 호스트 관리형 토큰을 사용하면 `auth.json` 원클릭을 차단합니다. 별도 App Server에서 파일 인증을 확인해도 공식 데스크톱 계정이 바뀌었다는 증거가 아니기 때문입니다.
- 공식 App Server에서 별도 데스크톱 호스트의 내부 토큰 상태를 가로채거나 private Keychain 토큰을 복사·주입하지 않습니다. `공식 로그인`은 macOS가 노출한 공식 앱 메뉴의 `로그아웃` 동작만 실행합니다.
- 과거 파일 기반 인증 환경에서 실제 두 계정 사이의 동일 task 재개와 후속 코드 작업은 **PASS**로 확인했습니다. 이 결과는 호스트 관리 인증 버전의 무로그인 계정 전환을 보장하지 않습니다.

## 설계와 문제 해결

- [아키텍처](docs/ARCHITECTURE.md)
- [보안 정책](SECURITY.md)
- [환경 진단](docs/ENVIRONMENT_REPORT.md)
- [세션 연속성 보고서](docs/SESSION_CONTINUITY_REPORT.md)
- [문제 해결](docs/TROUBLESHOOTING.md)
