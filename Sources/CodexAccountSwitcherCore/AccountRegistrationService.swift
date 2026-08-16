import Foundation

public enum LoginFlow: Sendable {
    case browser
    case deviceCode
}

public struct LoginChallenge: Equatable, Sendable {
    public var loginID: String
    public var verificationURL: URL
    public var userCode: String?

    public init(loginID: String, verificationURL: URL, userCode: String?) {
        self.loginID = loginID
        self.verificationURL = verificationURL
        self.userCode = userCode
    }
}

public struct AccountRegistrationService: Sendable {
    private let binaryURL: URL
    private let profileStore: EncryptedProfileStore
    private let writer = AtomicFileWriter()

    public init(binaryURL: URL, profileStore: EncryptedProfileStore) {
        self.binaryURL = binaryURL
        self.profileStore = profileStore
    }

    public func register(
        flow: LoginFlow = .browser,
        displayName: String? = nil,
        presentChallenge: @escaping @Sendable (LoginChallenge) async -> Bool
    ) async throws -> AccountProfile {
        let existing = try await profileStore.loadProfiles()
        guard existing.count < 2 else { throw SwitcherError.profileLimitReached }

        let temporaryHome = FileManager.default.temporaryDirectory
            .appending(path: "codex-account-switcher-login-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: temporaryHome,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer {
            SecureTemporaryFile.removeBestEffort(at: temporaryHome.appending(path: "auth.json"))
            try? FileManager.default.removeItem(at: temporaryHome)
        }
        let config = Data("cli_auth_credentials_store = \"file\"\n".utf8)
        try writer.write(config, to: temporaryHome.appending(path: "config.toml"))

        let connection = AppServerConnection(binaryURL: binaryURL, codexHome: temporaryHome)
        try await connection.start()
        defer { connection.stop() }

        async let completion = connection.waitForNotification(method: "account/login/completed", timeout: 600)
        let params: JSONValue
        switch flow {
        case .browser:
            params = .object([
                "type": .string("chatgpt"),
                "useHostedLoginSuccessPage": .bool(true),
                "appBrand": .string("chatgpt")
            ])
        case .deviceCode:
            params = .object(["type": .string("chatgptDeviceCode")])
        }
        let start = try await connection.request(method: "account/login/start", params: params)
        guard
            let loginID = start["loginId"]?.stringValue,
            let urlString = start[flow == .browser ? "authUrl" : "verificationUrl"]?.stringValue,
            let url = URL(string: urlString)
        else {
            throw SwitcherError.appServer("로그인 시작 응답 형식이 올바르지 않습니다")
        }
        let challenge = LoginChallenge(
            loginID: loginID,
            verificationURL: url,
            userCode: start["userCode"]?.stringValue
        )
        guard await presentChallenge(challenge) else {
            _ = try? await connection.request(
                method: "account/login/cancel",
                params: .object(["loginId": .string(loginID)])
            )
            throw SwitcherError.accountVerificationFailed("사용자가 로그인을 취소했습니다")
        }
        let completed = try await completion
        guard completed["success"]?.boolValue == true else {
            let message = completed["error"]?.stringValue ?? "로그인이 완료되지 않았습니다"
            throw SwitcherError.accountVerificationFailed(Redactor.redact(message))
        }

        let accountResult = try await connection.request(
            method: "account/read",
            params: .object(["refreshToken": .bool(false)])
        )
        guard let identity = try CodexAppServerClient.parseAccount(accountResult) else {
            throw SwitcherError.accountVerificationFailed("로그인 후 계정 정보가 없습니다")
        }
        let authFile = temporaryHome.appending(path: "auth.json")
        let authData = try Data(contentsOf: authFile, options: .mappedIfSafe)
        try AuthCacheValidator.validate(authData)

        let defaultName = "\((identity.planType ?? "ChatGPT").capitalized) Account \(existing.count + 1)"
        let profile = AccountProfile(
            displayName: displayName?.isEmpty == false ? displayName! : defaultName,
            maskedEmail: Redactor.maskEmail(identity.email),
            planType: identity.planType,
            lastValidatedAt: Date(),
            isActive: false
        )
        let secret = ProfileSecret(
            authCache: authData,
            accountEmail: identity.email,
            planType: identity.planType
        )
        return try await profileStore.save(profile: profile, secret: secret)
    }
}
