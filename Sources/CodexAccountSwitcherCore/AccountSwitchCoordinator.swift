import Foundation

public protocol AccountProbing: Sendable {
    func readAccount(refreshToken: Bool) async throws -> AccountIdentity?
    func readRateLimits() async throws -> AccountRateLimits?
}

extension CodexAppServerClient: AccountProbing {}

@MainActor
public final class AccountSwitchCoordinator {
    private let paths: SwitcherPaths
    private let officialApp: OfficialAppInfo
    private let profileStore: EncryptedProfileStore
    private let accountProbe: any AccountProbing
    private let appController: any OfficialAppControlling
    private let processScanner: any CodexProcessScanning
    private let processController: CodexProcessController
    private let preflight: any AccountSwitchPreflighting
    private let snapshotter: SessionSnapshotter
    private let recoveryStore: RecoveryStore
    private let writer: AtomicFileWriter

    public init(
        paths: SwitcherPaths,
        officialApp: OfficialAppInfo,
        profileStore: EncryptedProfileStore,
        accountProbe: any AccountProbing,
        appController: any OfficialAppControlling = OfficialAppController(),
        processScanner: any CodexProcessScanning = CodexProcessScanner(),
        processController: CodexProcessController? = nil,
        preflight: (any AccountSwitchPreflighting)? = nil,
        snapshotter: SessionSnapshotter? = nil,
        recoveryStore: RecoveryStore? = nil,
        writer: AtomicFileWriter = AtomicFileWriter()
    ) {
        self.paths = paths
        self.officialApp = officialApp
        self.profileStore = profileStore
        self.accountProbe = accountProbe
        self.appController = appController
        self.processScanner = processScanner
        self.processController = processController ?? CodexProcessController(scanner: processScanner)
        self.preflight = preflight ?? AccountSwitchPreflight(
            paths: paths,
            officialApp: officialApp,
            processScanner: processScanner,
            accountProbe: accountProbe
        )
        self.snapshotter = snapshotter ?? SessionSnapshotter(codexHome: paths.codexHome)
        self.recoveryStore = recoveryStore ?? RecoveryStore(paths: paths)
        self.writer = writer
    }

    public func switchAccount(
        to targetProfileID: UUID,
        forceQuitApproved: Bool = false,
        closeConflictingProcessesApproved: Bool = false,
        onPhase: @escaping @MainActor (SwitchPhase) -> Void
    ) async throws -> SwitchResult {
        let switchLock = try SwitchLock.acquire(at: paths.switchLockFile)
        _ = switchLock
        var authenticationChanged = false
        var previousAuthentication: Data?
        var previousIdentity: AccountIdentity?
        var previousActiveProfileID: UUID?

        do {
            onPhase(.checkingProcesses)
            let processes = try processScanner.scan(officialAppPath: officialApp.path)
            let blockers = processes.filter(\.blocksSwitch).map(\.safeDescription)
            if !blockers.isEmpty {
                guard closeConflictingProcessesApproved else {
                    throw SwitcherError.activeProcessConflict(blockers)
                }
                onPhase(.closingConflictingProcesses)
                try await processController.closeConflictingProcesses(officialAppPath: officialApp.path)
                let remaining = try processScanner.scan(officialAppPath: officialApp.path)
                    .filter(\.blocksSwitch)
                    .map(\.safeDescription)
                guard remaining.isEmpty else {
                    throw SwitcherError.activeProcessTerminationFailed(remaining)
                }
            }

            onPhase(.checkingAuthenticationSource)
            try await preflight.validateBeforeSwitch()

            onPhase(.snapshottingSessions)
            let before = try snapshotter.capture()
            let targetSecret = try await profileStore.secret(for: targetProfileID)
            try AuthCacheValidator.validate(targetSecret.authCache)

            onPhase(.savingCurrentAccount)
            let profiles = try await profileStore.loadProfiles()
            previousActiveProfileID = profiles.first(where: \.isActive)?.id
            previousIdentity = try await accountProbe.readAccount(refreshToken: true)
            if FileManager.default.fileExists(atPath: paths.authFile.path) {
                let currentAuthentication = try Data(contentsOf: paths.authFile, options: .mappedIfSafe)
                try AuthCacheValidator.validate(currentAuthentication)
                previousAuthentication = currentAuthentication
                if let previousActiveProfileID, let previousIdentity {
                    try await profileStore.updateCachedAuthentication(
                        profileID: previousActiveProfileID,
                        authCache: currentAuthentication,
                        identity: previousIdentity
                    )
                }
            }
            guard let previousAuthentication else {
                throw SwitcherError.invalidAuthenticationCache
            }

            onPhase(.quittingOfficialApp)
            let didQuit = await appController.requestNormalQuit(officialApp, timeout: 15)
            if !didQuit {
                guard forceQuitApproved else { throw SwitcherError.forceQuitApprovalRequired }
                try appController.forceQuit(officialApp, userApproved: true)
                try? await Task.sleep(for: .seconds(1))
                guard !appController.isRunning(officialApp) else {
                    throw SwitcherError.officialAppQuitTimedOut
                }
            }

            onPhase(.backingUpAuthentication)
            try recoveryStore.createBackup(from: previousAuthentication)
            let quiescentBefore = try snapshotter.capture(mode: .metadataOnly)

            onPhase(.replacingAuthentication)
            try writer.write(targetSecret.authCache, to: paths.authFile)
            guard try writer.permissions(of: paths.authFile) == 0o600 else {
                throw SwitcherError.fileOperation("활성 인증 파일 권한이 0600이 아닙니다")
            }
            authenticationChanged = true

            onPhase(.validatingAccount)
            guard let targetIdentity = try await accountProbe.readAccount(refreshToken: true) else {
                throw SwitcherError.accountVerificationFailed("account/read가 인증되지 않은 상태를 반환했습니다")
            }
            try verify(identity: targetIdentity, matches: targetSecret)
            try await profileStore.markActive(targetProfileID, identity: targetIdentity)

            onPhase(.verifyingAuthenticationIsolation)
            let quiescentAfter = try snapshotter.capture(mode: .metadataOnly)
            let isolationComparison = snapshotter.compare(quiescentBefore, quiescentAfter)
            guard isolationComparison.isUnchanged else {
                let changedPaths = (
                    isolationComparison.deleted
                        + isolationComparison.modified
                        + isolationComparison.added
                ).sorted()
                throw SwitcherError.protectedStateChangedDuringSwitch(changedPaths)
            }

            onPhase(.relaunchingOfficialApp)
            try await appController.launch(officialApp)
            try? await Task.sleep(for: .seconds(1))
            guard appController.isRunning(officialApp) else {
                throw SwitcherError.fileOperation("공식 앱 재실행을 확인하지 못했습니다")
            }
            try await preflight.validateAfterLaunch()

            onPhase(.verifyingSessionProtection)
            let after = try snapshotter.capture()
            let comparison = snapshotter.compare(before, after)
            if comparison.hasDestructiveChange {
                throw SwitcherError.sessionFilesMissing(comparison.deleted)
            }

            let limits = try? await accountProbe.readRateLimits()
            onPhase(.completed)
            return SwitchResult(account: targetIdentity, snapshotChanges: comparison, rateLimits: limits)
        } catch {
            guard authenticationChanged, let previousAuthentication else { throw error }
            onPhase(.rollingBack)
            do {
                guard await appController.requestNormalQuit(officialApp, timeout: 5) else {
                    throw SwitcherError.officialAppQuitTimedOut
                }
                try writer.write(previousAuthentication, to: paths.authFile)
                guard try writer.permissions(of: paths.authFile) == 0o600 else {
                    throw SwitcherError.fileOperation("롤백된 인증 파일 권한이 0600이 아닙니다")
                }
                if let previousActiveProfileID, let previousIdentity {
                    try await profileStore.markActive(previousActiveProfileID, identity: previousIdentity)
                } else {
                    try await profileStore.clearActiveProfile()
                }
                try await appController.launch(officialApp)
                guard appController.isRunning(officialApp) else {
                    throw SwitcherError.fileOperation("롤백 후 공식 앱 재실행을 확인하지 못했습니다")
                }
                if previousIdentity != nil {
                    guard let restored = try await accountProbe.readAccount(refreshToken: false) else {
                        throw SwitcherError.accountVerificationFailed("롤백 후 계정이 인증되지 않았습니다")
                    }
                    if let expectedEmail = previousIdentity?.email, let actualEmail = restored.email,
                       expectedEmail.caseInsensitiveCompare(actualEmail) != .orderedSame {
                        throw SwitcherError.accountMismatch(
                            expected: Redactor.maskEmail(expectedEmail) ?? "unknown",
                            actual: Redactor.maskEmail(actualEmail) ?? "unknown"
                        )
                    }
                }
            } catch let rollbackError {
                throw SwitcherError.rollbackFailed(Redactor.redact(rollbackError.localizedDescription))
            }
            throw error
        }
    }

    public func emergencyRestore() async throws {
        guard await appController.requestNormalQuit(officialApp, timeout: 10) else {
            throw SwitcherError.officialAppQuitTimedOut
        }
        try recoveryStore.restoreLatest()
        try await appController.launch(officialApp)
        guard appController.isRunning(officialApp) else {
            throw SwitcherError.fileOperation("긴급 복구 후 공식 앱 재실행을 확인하지 못했습니다")
        }
        guard try await accountProbe.readAccount(refreshToken: false) != nil else {
            throw SwitcherError.accountVerificationFailed("긴급 복구 후 계정을 확인하지 못했습니다")
        }
    }

    private func verify(identity: AccountIdentity, matches secret: ProfileSecret) throws {
        guard identity.type == "chatgpt" else {
            throw SwitcherError.accountVerificationFailed("ChatGPT 관리형 인증이 아닙니다")
        }
        if let expected = secret.accountEmail, let actual = identity.email,
           expected.caseInsensitiveCompare(actual) != .orderedSame {
            throw SwitcherError.accountMismatch(
                expected: Redactor.maskEmail(expected) ?? "unknown",
                actual: Redactor.maskEmail(actual) ?? "unknown"
            )
        }
        if secret.accountEmail != nil, identity.email == nil {
            throw SwitcherError.accountVerificationFailed("계정 이메일을 검증할 수 없습니다")
        }
    }
}
