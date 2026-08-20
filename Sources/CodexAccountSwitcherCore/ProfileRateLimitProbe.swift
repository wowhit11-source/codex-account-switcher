import Foundation

public struct ProfileRateLimitProbeResult: Sendable {
    public var account: AccountIdentity
    public var rateLimits: AccountRateLimits?
    public var rateLimitErrorDescription: String?
    public var refreshedAuthCache: Data
    public var checkedAt: Date

    public init(
        account: AccountIdentity,
        rateLimits: AccountRateLimits?,
        rateLimitErrorDescription: String? = nil,
        refreshedAuthCache: Data,
        checkedAt: Date = Date()
    ) {
        self.account = account
        self.rateLimits = rateLimits
        self.rateLimitErrorDescription = rateLimitErrorDescription
        self.refreshedAuthCache = refreshedAuthCache
        self.checkedAt = checkedAt
    }
}

/// Reads one encrypted profile's Codex limits without replacing the user's
/// shared CODEX_HOME. Plaintext authentication exists only inside a private,
/// randomly named temporary home and is removed immediately after the probe.
public struct ProfileRateLimitProbe: Sendable {
    private let binaryURL: URL
    private let writer: AtomicFileWriter

    public init(binaryURL: URL, writer: AtomicFileWriter = AtomicFileWriter()) {
        self.binaryURL = binaryURL
        self.writer = writer
    }

    public func read(secret: ProfileSecret) async throws -> ProfileRateLimitProbeResult {
        try AuthCacheValidator.validate(secret.authCache)

        let temporaryHome = FileManager.default.temporaryDirectory
            .appending(path: "codex-account-switcher-usage-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: temporaryHome,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )

        let authFile = temporaryHome.appending(path: "auth.json")
        defer {
            SecureTemporaryFile.removeBestEffort(at: authFile)
            try? FileManager.default.removeItem(at: temporaryHome)
        }

        try writer.write(Data("cli_auth_credentials_store = \"file\"\n".utf8), to: temporaryHome.appending(path: "config.toml"))
        try writer.write(secret.authCache, to: authFile)

        let connection = AppServerConnection(binaryURL: binaryURL, codexHome: temporaryHome)
        try await connection.start()
        defer { connection.stop() }

        let accountResult = try await connection.request(
            method: "account/read",
            params: .object(["refreshToken": .bool(false)])
        )
        guard let account = try CodexAppServerClient.parseAccount(accountResult) else {
            throw SwitcherError.accountVerificationFailed("저장 프로필의 계정 정보를 확인하지 못했습니다")
        }
        try verify(account: account, matches: secret)

        let rateLimits: AccountRateLimits?
        let rateLimitErrorDescription: String?
        do {
            let rateLimitResult = try await connection.request(method: "account/rateLimits/read")
            rateLimits = try CodexAppServerClient.parseRateLimits(rateLimitResult)
            rateLimitErrorDescription = nil
        } catch {
            // Account verification may refresh rotating credentials. Preserve
            // that refreshed cache even when this optional usage call fails.
            rateLimits = nil
            rateLimitErrorDescription = Redactor.redact(error.localizedDescription)
        }
        let refreshedAuthCache = try Data(contentsOf: authFile, options: .mappedIfSafe)
        try AuthCacheValidator.validate(refreshedAuthCache)

        return ProfileRateLimitProbeResult(
            account: account,
            rateLimits: rateLimits,
            rateLimitErrorDescription: rateLimitErrorDescription,
            refreshedAuthCache: refreshedAuthCache
        )
    }

    private func verify(account: AccountIdentity, matches secret: ProfileSecret) throws {
        guard let expectedEmail = secret.accountEmail else { return }
        guard let actualEmail = account.email else {
            throw SwitcherError.accountVerificationFailed("저장 프로필의 계정 이메일을 확인하지 못했습니다")
        }
        guard expectedEmail.caseInsensitiveCompare(actualEmail) == .orderedSame else {
            throw SwitcherError.accountMismatch(
                expected: Redactor.maskEmail(expectedEmail) ?? "unknown",
                actual: Redactor.maskEmail(actualEmail) ?? "unknown"
            )
        }
    }
}
