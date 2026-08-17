import Foundation
import XCTest
@testable import CodexAccountSwitcherCore

final class AtomicSnapshotAndRecoveryTests: XCTestCase {
    func testAtomicReplacementAnd0600Permissions() throws {
        let root = try TestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "auth.json")
        let writer = AtomicFileWriter()
        try writer.write(TestFixtures.authentication("a"), to: file)
        try writer.write(TestFixtures.authentication("b"), to: file)
        XCTAssertEqual(try Data(contentsOf: file), TestFixtures.authentication("b"))
        XCTAssertEqual(try writer.permissions(of: file), 0o600)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.contains(".tmp") })
    }

    func testSwitchLockRejectsConcurrentAcquisition() throws {
        let root = try TestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let lockURL = root.appending(path: "switch.lock")
        let first = try SwitchLock.acquire(at: lockURL)
        _ = first
        XCTAssertThrowsError(try SwitchLock.acquire(at: lockURL))
    }

    func testSessionSnapshotIgnoresAuthAndDetectsSessionChanges() throws {
        let root = try TestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = TestFixtures.paths(root: root)
        try TestFixtures.populateSharedState(paths)
        try AtomicFileWriter().write(TestFixtures.authentication("a"), to: paths.authFile)
        let snapshotter = SessionSnapshotter(codexHome: paths.codexHome)
        let before = try snapshotter.capture()

        try AtomicFileWriter().write(TestFixtures.authentication("b"), to: paths.authFile)
        let authOnly = snapshotter.compare(before, try snapshotter.capture())
        XCTAssertTrue(authOnly.isUnchanged)

        try Data("changed".utf8).write(to: paths.codexHome.appending(path: "sessions/2026/08/session.jsonl"))
        let changed = snapshotter.compare(before, try snapshotter.capture())
        XCTAssertEqual(changed.modified, ["sessions/2026/08/session.jsonl"])
    }

    func testMetadataSnapshotDetectsProtectedMutationWithoutHashingContents() throws {
        let root = try TestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = TestFixtures.paths(root: root)
        try TestFixtures.populateSharedState(paths)
        let snapshotter = SessionSnapshotter(codexHome: paths.codexHome)
        let session = paths.codexHome.appending(path: "sessions/2026/08/session.jsonl")
        let before = try snapshotter.capture(mode: .metadataOnly)

        try Data("session-mutated".utf8).write(to: session)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(2)],
            ofItemAtPath: session.path
        )

        let comparison = snapshotter.compare(before, try snapshotter.capture(mode: .metadataOnly))
        XCTAssertTrue(comparison.modified.contains("sessions/2026/08/session.jsonl"))
    }

    func testRecoveryStoreRollsAuthenticationBack() throws {
        let root = try TestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = TestFixtures.paths(root: root)
        let vault = CryptoVault(keyStore: MemoryKeyStore())
        let recovery = RecoveryStore(paths: paths, vault: vault)
        let original = TestFixtures.authentication("original")
        try AtomicFileWriter().write(original, to: paths.authFile)
        try recovery.createBackup(from: original)
        try AtomicFileWriter().write(TestFixtures.authentication("new"), to: paths.authFile)
        try recovery.restoreLatest()
        XCTAssertEqual(try Data(contentsOf: paths.authFile), original)
        XCTAssertEqual(try AtomicFileWriter().permissions(of: paths.authFile), 0o600)
    }

    func testSessionMarkerFinderReturnsExactSessionIDWithoutReadingSecrets() throws {
        let root = try TestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = TestFixtures.paths(root: root)
        let id = "019fd5d1-8a49-7380-a838-a13ed09603d1"
        let session = paths.codexHome.appending(path: "sessions/2026/08/rollout-\(id).jsonl")
        try FileManager.default.createDirectory(at: session.deletingLastPathComponent(), withIntermediateDirectories: true)
        let marker = "CAS-PROBE-\(UUID().uuidString)"
        try Data("{\"message\":\"\(marker)\"}".utf8).write(to: session)
        let match = try SessionMarkerFinder(codexHome: paths.codexHome).find(marker: marker)
        XCTAssertEqual(match?.fileURL.resolvingSymlinksInPath(), session.resolvingSymlinksInPath())
        XCTAssertEqual(match?.sessionID, id)
    }
}
