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

    public init(isAvailable: Bool, reason: String? = nil) {
        self.isAvailable = isAvailable
        self.reason = reason
    }

    public static let available = OneClickSwitchAvailability(isAvailable: true)

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
        if officialAppAuthenticationMode == .hostManaged {
            return .unavailable(
                "공식 앱이 호스트 관리 인증을 사용해 auth.json 교체가 앱 계정 전환을 보장하지 않습니다. "
                    + "공식 앱에서 직접 계정을 바꾸세요."
            )
        }

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
    private let postLaunchObservationDuration: Duration
    private let postLaunchPollInterval: Duration

    public init(
        paths: SwitcherPaths,
        officialApp: OfficialAppInfo,
        processScanner: any CodexProcessScanning,
        accountProbe: any AccountProbing,
        postLaunchObservationDuration: Duration = .seconds(2),
        postLaunchPollInterval: Duration = .milliseconds(250)
    ) {
        self.paths = paths
        self.officialApp = officialApp
        self.processScanner = processScanner
        self.accountProbe = accountProbe
        self.postLaunchObservationDuration = postLaunchObservationDuration
        self.postLaunchPollInterval = postLaunchPollInterval
    }

    public func validateBeforeSwitch() async throws {
        let mode = try officialAuthenticationMode()
        let configURL = paths.codexHome.appending(path: "config.toml")
        let setting = CodexCredentialsStoreMode.configuredValue(at: configURL)
        let store = CodexCredentialsStoreMode(configuredValue: setting)

        if mode == .hostManaged {
            try throwUnavailable(
                AccountSwitchPreflightPolicy.evaluate(
                    credentialsStoreSetting: setting,
                    authFileExists: FileManager.default.fileExists(atPath: paths.authFile.path),
                    officialAppAuthenticationMode: mode,
                    runtimeIdentityAvailable: false
                )
            )
        }
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
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: postLaunchObservationDuration)
        while true {
            guard try officialAuthenticationMode() != .hostManaged else {
                throw SwitcherError.oneClickSwitchUnavailable(
                    "재실행된 공식 앱이 호스트 관리 인증을 사용해 전환된 auth.json을 실제 앱 계정으로 검증할 수 없습니다."
                )
            }
            guard clock.now < deadline else { return }
            if postLaunchPollInterval > .zero {
                try await Task.sleep(for: postLaunchPollInterval)
            }
        }
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
