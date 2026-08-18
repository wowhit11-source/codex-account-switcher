import AppKit
import Foundation

@MainActor
public final class OfficialAppAccountController {
    public init() {}

    public func requestLogout(
        _ app: OfficialAppInfo,
        timeout: TimeInterval = 5
    ) async throws {
        let source = Self.logoutScript(bundleIdentifier: app.bundleIdentifier)
        let deadline = Date().addingTimeInterval(timeout)
        var lastFailure = "공식 앱의 로그아웃 메뉴를 찾지 못했습니다."

        repeat {
            do {
                try Self.executeAppleScript(source)
                return
            } catch SwitcherError.officialAppLogoutFailed(let message) {
                lastFailure = message
                if message.contains("자동화 권한") {
                    throw SwitcherError.officialAppLogoutFailed(message)
                }
            }

            if Date() >= deadline { break }
            try await Task.sleep(for: .milliseconds(250))
        } while true

        throw SwitcherError.officialAppLogoutFailed(lastFailure)
    }

    nonisolated static func logoutScript(bundleIdentifier: String) -> String {
        let escapedBundleIdentifier = bundleIdentifier
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "System Events"
            set candidates to every application process whose bundle identifier is "\(escapedBundleIdentifier)"
            if (count of candidates) is 0 then error "공식 앱 프로세스를 찾지 못했습니다" number -600
            set targetProcess to item 1 of candidates
            tell targetProcess
                set frontmost to true
                set appMenu to menu 1 of menu bar item 2 of menu bar 1
                set logoutNames to {"Log Out", "Logout", "Sign Out", "로그아웃"}
                repeat with candidateName in logoutNames
                    if exists menu item (candidateName as text) of appMenu then
                        click menu item (candidateName as text) of appMenu
                        return "logout-requested"
                    end if
                end repeat
            end tell
            error "공식 앱의 로그아웃 메뉴를 찾지 못했습니다" number -1728
        end tell
        """
    }

    nonisolated static func failureMessage(errorNumber: Int?, message: String?) -> String {
        if errorNumber == -1743 {
            return "macOS 자동화 권한이 거부되었습니다. 시스템 설정 > 개인정보 보호 및 보안 > 자동화에서 Codex Account Switcher의 System Events 권한을 허용하세요."
        }
        return Redactor.redact(message ?? "AppleScript 실행 오류")
    }

    private static func executeAppleScript(_ source: String) throws {
        guard let script = NSAppleScript(source: source) else {
            throw SwitcherError.officialAppLogoutFailed("로그아웃 자동화 스크립트를 만들지 못했습니다.")
        }
        var errorInfo: NSDictionary?
        _ = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let number = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue
            let message = errorInfo[NSAppleScript.errorMessage] as? String
            throw SwitcherError.officialAppLogoutFailed(
                failureMessage(errorNumber: number, message: message)
            )
        }
    }
}
