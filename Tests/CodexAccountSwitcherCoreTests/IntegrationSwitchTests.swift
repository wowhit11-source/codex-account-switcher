import Foundation
import XCTest
@testable import CodexAccountSwitcherCore

final class IntegrationSwitchTests: XCTestCase {
    func testTenSwitchesChangeOnlyAuthenticationAndKeepLogsSecretFree() async throws {
        let root = try TestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = TestFixtures.paths(root: root)
        try TestFixtures.populateSharedState(paths)
        let writer = AtomicFileWriter()
        let vault = CryptoVault(keyStore: MemoryKeyStore())
        let store = EncryptedProfileStore(paths: paths, vault: vault)
        let accountA = AccountProfile(displayName: "Account A", maskedEmail: "a***@example.com", planType: "pro", isActive: true)
        let accountB = AccountProfile(displayName: "Account B", maskedEmail: "b***@example.com", planType: "pro")
        _ = try await store.save(
            profile: accountA,
            secret: ProfileSecret(authCache: TestFixtures.authentication("account-a"), accountEmail: "a@example.com", planType: "pro")
        )
        _ = try await store.save(
            profile: accountB,
            secret: ProfileSecret(authCache: TestFixtures.authentication("account-b"), accountEmail: "b@example.com", planType: "pro")
        )
        try writer.write(TestFixtures.authentication("account-a"), to: paths.authFile)

        let snapshotter = SessionSnapshotter(codexHome: paths.codexHome)
        let baseline = try snapshotter.capture()
        for index in 0..<10 {
            let target = index.isMultiple(of: 2) ? accountB.id : accountA.id
            let secret = try await store.secret(for: target)
            try AuthCacheValidator.validate(secret.authCache)
            try writer.write(secret.authCache, to: paths.authFile)
            XCTAssertEqual(try writer.permissions(of: paths.authFile), 0o600)
            XCTAssertTrue(snapshotter.compare(baseline, try snapshotter.capture()).isUnchanged)
        }

        XCTAssertEqual(try Data(contentsOf: paths.codexHome.appending(path: "history.jsonl")), Data("history-stable".utf8))
        XCTAssertEqual(try Data(contentsOf: paths.codexHome.appending(path: "sessions/2026/08/session.jsonl")), Data("session-stable".utf8))
        XCTAssertEqual(try Data(contentsOf: paths.codexHome.appending(path: "config.toml")), Data("config-stable".utf8))
        XCTAssertEqual(try Data(contentsOf: paths.codexHome.appending(path: "skills/example/SKILL.md")), Data("skill-stable".utf8))

        let rawLog = "access_token=fixture-account-a refresh_token=refresh-account-a authorization=Bearer hidden"
        let safeLog = Redactor.redact(rawLog)
        let logURL = root.appending(path: "switch.log")
        try Data(safeLog.utf8).write(to: logURL)
        let persistedLog = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertFalse(persistedLog.contains("fixture-account-a"))
        XCTAssertFalse(persistedLog.contains("refresh-account-a"))
        XCTAssertFalse(persistedLog.contains("Bearer hidden"))
    }

    func testMidSwitchFailureRestoresPreviousAuthentication() throws {
        let root = try TestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = TestFixtures.paths(root: root)
        let vault = CryptoVault(keyStore: MemoryKeyStore())
        let recovery = RecoveryStore(paths: paths, vault: vault)
        let original = TestFixtures.authentication("account-a")
        try AtomicFileWriter().write(original, to: paths.authFile)
        try recovery.createBackup(from: original)

        try AtomicFileWriter().write(TestFixtures.authentication("account-b"), to: paths.authFile)
        let simulatedVerificationSucceeded = false
        if !simulatedVerificationSucceeded {
            try recovery.restoreLatest()
        }
        XCTAssertEqual(try Data(contentsOf: paths.authFile), original)
    }
}
