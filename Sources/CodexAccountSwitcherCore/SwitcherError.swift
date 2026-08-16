import Foundation

public enum SwitcherError: Error, LocalizedError, Sendable {
    case unsupportedEnvironment(String)
    case invalidAuthenticationCache
    case keychain(String)
    case cryptography(String)
    case profileLimitReached
    case profileNotFound
    case activeProcessConflict([String])
    case activeProcessTerminationFailed([String])
    case officialAppNotFound
    case officialAppQuitTimedOut
    case forceQuitApprovalRequired
    case accountMismatch(expected: String, actual: String)
    case accountVerificationFailed(String)
    case appServer(String)
    case switchAlreadyInProgress
    case sessionFilesMissing([String])
    case rollbackFailed(String)
    case markerNotFound
    case fileOperation(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedEnvironment(let message):
            return "지원할 수 없는 환경입니다: \(message)"
        case .invalidAuthenticationCache:
            return "인증 캐시의 JSON 구조가 올바르지 않습니다."
        case .keychain(let message):
            return "Keychain 작업에 실패했습니다: \(message)"
        case .cryptography(let message):
            return "인증 캐시 암호화 작업에 실패했습니다: \(message)"
        case .profileLimitReached:
            return "초기 버전에서는 계정을 최대 두 개까지 등록할 수 있습니다."
        case .profileNotFound:
            return "선택한 계정 프로필을 찾지 못했습니다."
        case .activeProcessConflict(let processes):
            let visible = processes.prefix(5).joined(separator: ", ")
            let remainder = max(processes.count - 5, 0)
            let suffix = remainder > 0 ? ", 외 \(remainder)개" : ""
            return "Codex CLI 또는 IDE 세션 \(processes.count)개가 열린 상태여서 전환을 중단했습니다. "
                + "작업 중이 아니어도 인증 충돌을 막기 위해 해당 세션에서 exit 또는 Ctrl+C로 정상 종료해야 합니다. "
                + "감지: \(visible)\(suffix)"
        case .activeProcessTerminationFailed(let processes):
            let visible = processes.prefix(5).joined(separator: ", ")
            let remainder = max(processes.count - 5, 0)
            let suffix = remainder > 0 ? ", 외 \(remainder)개" : ""
            return "Codex CLI 세션을 정상 종료하지 못해 전환하지 않았습니다. 감지: \(visible)\(suffix)"
        case .officialAppNotFound:
            return "공식 ChatGPT/Codex 앱을 찾지 못했습니다."
        case .officialAppQuitTimedOut:
            return "공식 앱이 15초 안에 정상 종료되지 않았습니다."
        case .forceQuitApprovalRequired:
            return "강제 종료에는 사용자의 명시적 승인이 필요합니다."
        case .accountMismatch(let expected, let actual):
            return "검증된 계정이 선택한 프로필과 다릅니다. 예상: \(expected), 실제: \(actual)"
        case .accountVerificationFailed(let message):
            return "새 계정을 검증하지 못했습니다: \(message)"
        case .appServer(let message):
            return "Codex App Server 오류: \(message)"
        case .switchAlreadyInProgress:
            return "다른 계정 전환이 이미 진행 중입니다."
        case .sessionFilesMissing(let paths):
            return "보호 대상 세션 파일이 사라졌습니다: \(paths.joined(separator: ", "))"
        case .rollbackFailed(let message):
            return "자동 롤백에 실패했습니다: \(message)"
        case .markerNotFound:
            return "로컬 세션 저장소에서 연속성 테스트 마커를 찾지 못했습니다."
        case .fileOperation(let message):
            return "파일 작업에 실패했습니다: \(message)"
        }
    }
}
