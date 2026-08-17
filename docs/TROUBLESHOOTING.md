# Troubleshooting

## 공식 앱을 찾지 못함

Switcher는 `/Applications`와 `~/Applications`의 앱을 열어 `Info.plist`, `com.openai.*` Bundle Identifier, 번들 `Contents/Resources/codex` 실행 파일을 함께 확인합니다. 이름만 ChatGPT/Codex인 앱은 선택하지 않습니다. 공식 앱을 기본 위치에 다시 설치한 뒤 새로고침하세요.

## 다른 Codex 작업이 실행 중이라는 경고

별도 `codex` CLI나 IDE 세션이 남아 있습니다. Switcher는 감지된 세션을 보여주고 `CLI 종료 후 전환` 승인을 요청합니다. 승인하면 `SIGINT`와 `SIGTERM`으로만 정상 종료를 시도하며, 종료되지 않으면 인증 변경 전에 중단합니다. 공식 ChatGPT 앱의 번들 App Server 자식은 정상 종료 대상이므로 별도 blocker로 보지 않습니다.

## 공식 앱이 15초 안에 종료되지 않음

먼저 공식 앱의 실행 중 작업을 확인하고 직접 종료하세요. 다시 전환했는데도 종료되지 않으면 앱이 강제 종료 승인을 한 번 더 묻습니다. 승인 없이 강제 종료하지 않습니다.

## Keychain 오류

Keychain이 잠겨 있거나 앱 서명/사용자 세션 문제일 수 있습니다. Mac 로그인 Keychain을 잠금 해제하고 앱을 다시 실행하세요. Keychain 오류 시 평문 저장으로 우회하지 않습니다.

승인창에서 `허용`은 이번 접근만 승인하고 `항상 허용`은 현재 서명된 설치본의 이후 접근도 승인합니다. Switcher는 키를 프로세스 메모리에 캐시하므로 `허용`을 선택해도 한 번의 실행 중에는 승인창이 한 번만 나타납니다. ad-hoc 서명 빌드를 재설치하면 최초 승인이 다시 필요할 수 있습니다.

## App Server 초기화 실패

환경 보고서의 번들 Codex 경로와 버전을 확인하세요. 이 앱은 `initialize` 응답을 받은 뒤 `initialized` 알림을 보내고 account 메서드를 호출합니다. `CODEX_HOME`의 SQLite 상태 파일이 다른 샌드박스에서 쓰기 금지된 경우 App Server가 시작되지 않을 수 있습니다. 설치된 `.app`을 Finder 또는 `open`으로 실행해 실제 사용자 권한에서 확인하세요.

## 사용량 정보 없음

`account/rateLimits/read`가 인증 모드 또는 서비스 상태 때문에 응답하지 않은 경우입니다. 추정값은 표시하지 않습니다. 현재 계정 새로고침 후 다시 확인하세요. API-key-only 또는 Bedrock 인증에서는 ChatGPT 사용량이 없을 수 있습니다.

## 계정 불일치로 자동 롤백

대상 프로필에 암호화 저장된 전체 이메일과 `account/read` 결과가 다르면 즉시 이전 인증으로 돌아갑니다. 프로필을 삭제하고 공식 browser/device-code 로그인으로 다시 등록하세요. 이메일 원문은 암호문 안에만 있고 일반 로그에는 마스킹됩니다.

## 공식 앱이 auth.json 전환을 무시함

데스크톱 호스트가 자체 `chatgptAuthTokens`를 주입하는 버전일 수 있습니다. 이 모드에서도 유효한 파일 인증이 확인되면 프로필의 `전환` 버튼을 호환 모드로 제공합니다. 공식 앱을 패치하거나 private Keychain 토큰을 복사하지 않으며, 전환 후 공식 앱의 계정 메뉴에서 실제 계정이 바뀌었는지 확인하세요. 바뀌지 않았다면 `Guided Switch`로 직접 로그아웃·로그인하고, Continuity Test에서 동일 thread 후속 실행을 확인하세요.

`cli_auth_credentials_store = "keyring"`이거나 알 수 없는 값이면 같은 이유로 원클릭 전환을 차단합니다. `file`, `auto`, 미설정 환경은 유효한 `auth.json`과 새 App Server의 실제 계정 응답이 모두 확인될 때만 허용됩니다.

## Session Continuity가 PARTIAL 또는 FAIL

- PARTIAL: 로컬 파일과 목록은 남았지만 계정 B가 후속 작업을 거부했거나 새 thread로 분기한 경우
- FAIL: 기존 세션이 사라지거나 열리지 않는 경우

세션 파일 존재만으로 PASS로 바꾸지 마세요. 계정 A로 즉시 돌아가고 긴급복구 백업이 필요하면 공식 앱을 종료한 뒤 실행합니다.

```bash
./scripts/emergency-restore.sh
```

## 빌드 캐시 경고

외장 볼륨이나 제한된 실행 환경에서는 SwiftPM의 사용자 cache 또는 nested sandbox가 거부될 수 있습니다. 제공된 `scripts/build.sh`와 `scripts/test.sh`는 프로젝트를 변경하지 않는 `/private/tmp` scratch/cache와 `--disable-sandbox`를 사용합니다. 이는 Codex 작업 샌드박스 중첩을 피하기 위한 빌드 설정이며, 완성 앱의 계정 전환 안전장치를 비활성화하지 않습니다.

## 완전 삭제

```bash
./scripts/uninstall.sh --purge-data
```

이 명령은 설치 앱, Switcher Application Support, Switcher 전용 Keychain 키만 제거합니다. `~/.codex`는 건드리지 않습니다.
