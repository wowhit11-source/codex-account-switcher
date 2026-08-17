import Foundation

public enum CodexCredentialsStoreMode: Equatable, Sendable {
    case file
    case keyring
    case auto
    case unspecified
    case unsupported(String)

    public init(configuredValue: String?) {
        guard let configuredValue else {
            self = .unspecified
            return
        }
        switch configuredValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "file": self = .file
        case "keyring": self = .keyring
        case "auto": self = .auto
        case "": self = .unspecified
        case let value: self = .unsupported(value)
        }
    }

    public static func configuredValue(at configURL: URL) -> String? {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return nil }
        let pattern = #"(?m)^\s*cli_auth_credentials_store\s*=\s*([^#\n]+)"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return text[range]
            .split(separator: "=", maxSplits: 1)
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
}

public struct OneClickSwitchAvailability: Equatable, Sendable {
    public var isAvailable: Bool
    public var reason: String?
    public var warning: String?

    public init(isAvailable: Bool, reason: String? = nil, warning: String? = nil) {
        self.isAvailable = isAvailable
        self.reason = reason
        self.warning = warning
    }

    public static let available = OneClickSwitchAvailability(isAvailable: true)

    public static func availableWithWarning(_ warning: String) -> OneClickSwitchAvailability {
        OneClickSwitchAvailability(isAvailable: true, warning: warning)
    }

    public static func unavailable(_ reason: String) -> OneClickSwitchAvailability {
        OneClickSwitchAvailability(isAvailable: false, reason: reason)
    }
}

public enum AccountSwitchPreflightPolicy {
    public static func evaluate(
        credentialsStoreSetting: String?,
        authFileExists: Bool,
        officialAppAuthenticationMode: OfficialAppAuthenticationMode,
        runtimeIdentityAvailable: Bool
    ) -> OneClickSwitchAvailability {
        switch CodexCredentialsStoreMode(configuredValue: credentialsStoreSetting) {
        case .keyring:
            return .unavailable(
                "cli_auth_credentials_store가 keyring으로 설정되어 auth.json이 인증 원본이 아닐 수 있습니다."
            )
        case .unsupported(let value):
            return .unavailable("지원하지 않는 cli_auth_credentials_store 값입니다: \(value)")
        case .file, .auto, .unspecified:
            break
        }

        guard authFileExists else {
            return .unavailable("유효한 auth.json이 없어 파일 기반 계정 전환을 확인할 수 없습니다.")
        }
        guard runtimeIdentityAvailable else {
            return .unavailable("auth.json 기반 계정을 새 Codex App Server에서 확인하지 못했습니다.")
        }
        if officialAppAuthenticationMode == .hostManaged {
            return .availableWithWarning(
                "호스트 관리 인증이 감지되어 호환 모드로 전환합니다. "
                    + "전환 후 공식 앱에서 실제 계정을 확인하세요."
            )
        }
        return .available
    }
}

public protocol AccountSwitchPreflighting: Sendable {
    func validateBeforeSwitch() async throws
    func validateAfterLaunch() async throws
}

public struct AccountSwitchPreflight: AccountSwitchPreflighting, Sendable {
    private let paths: SwitcherPaths
    private let officialApp: OfficialAppInfo
    private let processScanner: any CodexProcessScanning
    private let accountProbe: any AccountProbing

    public init(
        paths: SwitcherPaths,
        officialApp: OfficialAppInfo,
        processScanner: any CodexProcessScanning,
        accountProbe: any AccountProbing
    ) {
        self.paths = paths
        self.officialApp = officialApp
        self.processScanner = processScanner
        self.accountProbe = accountProbe
    }

    public func validateBeforeSwitch() async throws {
        let mode = try officialAuthenticationMode()
        let configURL = paths.codexHome.appending(path: "config.toml")
        let setting = CodexCredentialsStoreMode.configuredValue(at: configURL)
        let store = CodexCredentialsStoreMode(configuredValue: setting)

        switch store {
        case .keyring, .unsupported:
            try throwUnavailable(
                AccountSwitchPreflightPolicy.evaluate(
                    credentialsStoreSetting: setting,
                    authFileExists: FileManager.default.fileExists(atPath: paths.authFile.path),
                    officialAppAuthenticationMode: mode,
                    runtimeIdentityAvailable: false
                )
            )
        case .file, .auto, .unspecified:
            break
        }

        let authFileExists = FileManager.default.fileExists(atPath: paths.authFile.path)
        guard authFileExists else {
            try throwUnavailable(
                AccountSwitchPreflightPolicy.evaluate(
                    credentialsStoreSetting: setting,
                    authFileExists: false,
                    officialAppAuthenticationMode: mode,
                    runtimeIdentityAvailable: false
                )
            )
            return
        }
        do {
            try AuthCacheValidator.validate(Data(contentsOf: paths.authFile, options: .mappedIfSafe))
        } catch {
            throw SwitcherError.oneClickSwitchUnavailable(
                "auth.json의 인증 구조를 검증하지 못했습니다: \(Redactor.redact(error.localizedDescription))"
            )
        }

        let runtimeIdentityAvailable: Bool
        do {
            runtimeIdentityAvailable = try await accountProbe.readAccount(refreshToken: false) != nil
        } catch {
            throw SwitcherError.oneClickSwitchUnavailable(
                "auth.json 기반 계정을 확인하지 못했습니다: \(Redactor.redact(error.localizedDescription))"
            )
        }

        try throwUnavailable(
            AccountSwitchPreflightPolicy.evaluate(
                credentialsStoreSetting: setting,
                authFileExists: authFileExists,
                officialAppAuthenticationMode: mode,
                runtimeIdentityAvailable: runtimeIdentityAvailable
            )
        )
    }

    public func validateAfterLaunch() async throws {
        // Host-managed desktop builds are supported in compatibility mode.
        // The transaction has already validated the replaced auth.json through a fresh App Server;
        // the desktop account itself remains a user-visible post-switch confirmation.
    }

    private func officialAuthenticationMode() throws -> OfficialAppAuthenticationMode {
        let processes = try processScanner.scan(officialAppPath: officialApp.path)
        let officialProcesses = processes.filter(\.isOfficialAppProcess)
        guard !officialProcesses.isEmpty else { return .notRunning }
        return officialProcesses.contains(where: \.usesHostManagedAuthentication)
            ? .hostManaged
            : .standardOrUnknown
    }

    private func throwUnavailable(_ availability: OneClickSwitchAvailability) throws {
        guard !availability.isAvailable else { return }
        throw SwitcherError.oneClickSwitchUnavailable(availability.reason ?? "인증 저장 방식을 확인할 수 없습니다.")
    }
}
