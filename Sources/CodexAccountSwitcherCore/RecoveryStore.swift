import Foundation

public struct RecoveryStore: Sendable {
    private let paths: SwitcherPaths
    private let vault: CryptoVault
    private let writer: AtomicFileWriter

    public init(paths: SwitcherPaths = SwitcherPaths(), vault: CryptoVault = CryptoVault()) {
        self.paths = paths
        self.vault = vault
        self.writer = AtomicFileWriter()
    }

    public func createBackup(from authentication: Data) throws {
        try AuthCacheValidator.validate(authentication)
        try FileManager.default.createDirectory(
            at: paths.recoveryDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try writer.write(try vault.encrypt(authentication), to: paths.latestRecoveryFile)
    }

    public func restoreLatest() throws {
        guard FileManager.default.fileExists(atPath: paths.latestRecoveryFile.path) else {
            throw SwitcherError.fileOperation("긴급 복구 백업이 없습니다")
        }
        let encrypted = try Data(contentsOf: paths.latestRecoveryFile, options: .mappedIfSafe)
        let authentication = try vault.decrypt(encrypted)
        try AuthCacheValidator.validate(authentication)
        try writer.write(authentication, to: paths.authFile)
        guard try writer.permissions(of: paths.authFile) == 0o600 else {
            throw SwitcherError.fileOperation("복구된 인증 파일 권한이 0600이 아닙니다")
        }
    }

    public var hasBackup: Bool {
        FileManager.default.fileExists(atPath: paths.latestRecoveryFile.path)
    }
}
