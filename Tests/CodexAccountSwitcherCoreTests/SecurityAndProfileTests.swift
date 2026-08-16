import CryptoKit
import Foundation
import XCTest
@testable import CodexAccountSwitcherCore

final class SecurityAndProfileTests: XCTestCase {
    func testAESGCMRoundTripAndTamperRejection() throws {
        let vault = CryptoVault(keyStore: MemoryKeyStore())
        let plaintext = TestFixtures.authentication("account-a")
        let encrypted = try vault.encrypt(plaintext)
        XCTAssertNotEqual(encrypted, plaintext)
        XCTAssertEqual(try vault.decrypt(encrypted), plaintext)

        var tampered = encrypted
        tampered[tampered.index(before: tampered.endIndex)] ^= 0x01
        XCTAssertThrowsError(try vault.decrypt(tampered))
    }

    func testSystemKeychainGeneratesStable256BitKey() throws {
        let store = SystemKeychainStore(
            service: "com.yonghyunkim.CodexAccountSwitcher.tests.\(UUID().uuidString)",
            account: "test-key"
        )
        defer { try? store.deleteKey() }
        let first = try store.loadOrCreateKey().withUnsafeBytes { Data($0) }
        let second = try store.loadOrCreateKey().withUnsafeBytes { Data($0) }
        XCTAssertEqual(first.count, 32)
        XCTAssertEqual(first, second)
    }

    func testProcessKeyCacheReadsBackingStoreOnlyOnceUntilDeletion() throws {
        let backing = CountingKeyStore()
        let cached = ProcessCachedSecretKeyStore(backing: backing)

        let first = try cached.loadOrCreateKey().withUnsafeBytes { Data($0) }
        let second = try cached.loadOrCreateKey().withUnsafeBytes { Data($0) }

        XCTAssertEqual(first, second)
        XCTAssertEqual(backing.loadCount, 1)

        try cached.deleteKey()
        _ = try cached.loadOrCreateKey()

        XCTAssertEqual(backing.deleteCount, 1)
        XCTAssertEqual(backing.loadCount, 2)
    }

    func testAuthCacheValidatorRejectsMalformedAndCredentialFreeJSON() throws {
        XCTAssertThrowsError(try AuthCacheValidator.validate(Data("not-json".utf8)))
        XCTAssertThrowsError(try AuthCacheValidator.validate(Data("{\"theme\":\"dark\"}".utf8)))
        XCTAssertNoThrow(try AuthCacheValidator.validate(TestFixtures.authentication("valid")))
    }

    func testEncryptedProfileMetadataRoundTrip() async throws {
        let root = try TestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = TestFixtures.paths(root: root)
        let store = EncryptedProfileStore(paths: paths, vault: CryptoVault(keyStore: MemoryKeyStore()))
        let profile = AccountProfile(
            displayName: "Pro Account 1",
            maskedEmail: "u***@example.com",
            planType: "pro",
            isActive: true
        )
        let auth = TestFixtures.authentication("profile-secret")
        _ = try await store.save(
            profile: profile,
            secret: ProfileSecret(authCache: auth, accountEmail: "user@example.com", planType: "pro")
        )
        let loaded = try await store.loadProfiles()
        XCTAssertEqual(loaded, [profile])
        let loadedSecret = try await store.secret(for: profile.id)
        XCTAssertEqual(loadedSecret.authCache, auth)

        let encryptedURL = paths.profilesDirectory.appending(path: "\(profile.id.uuidString).casprofile")
        let encrypted = try Data(contentsOf: encryptedURL)
        XCTAssertNil(encrypted.range(of: Data("profile-secret".utf8)))
        XCTAssertEqual(try AtomicFileWriter().permissions(of: encryptedURL), 0o600)
        XCTAssertEqual(try AtomicFileWriter().permissions(of: paths.profileMetadataFile), 0o600)
    }

    func testProfileStoreEnforcesTwoAccountLimit() async throws {
        let root = try TestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = EncryptedProfileStore(paths: TestFixtures.paths(root: root), vault: CryptoVault(keyStore: MemoryKeyStore()))
        for index in 1...2 {
            _ = try await store.save(
                profile: AccountProfile(displayName: "Account \(index)"),
                secret: ProfileSecret(authCache: TestFixtures.authentication("\(index)"), accountEmail: "u\(index)@example.com", planType: "pro")
            )
        }
        await XCTAssertThrowsErrorAsync {
            _ = try await store.save(
                profile: AccountProfile(displayName: "Account 3"),
                secret: ProfileSecret(authCache: TestFixtures.authentication("3"), accountEmail: "u3@example.com", planType: "pro")
            )
        }
    }

    func testRedactionAndEmailMasking() {
        let raw = "authorization=Bearer abc.def access_token=secret sk-abcdefghijk eyJabcdefghijklm user@example.com"
        let redacted = Redactor.redact(raw)
        XCTAssertFalse(redacted.contains("abc.def"))
        XCTAssertFalse(redacted.contains("abcdefghijk"))
        XCTAssertFalse(redacted.contains("user@example.com"))
        XCTAssertEqual(Redactor.maskEmail("user@example.com"), "u***@example.com")
    }

    func testRedactionRemovesQuotedJSONTokenValues() {
        let raw = #"{"access_token":"fixture-access-token-json","refresh_token": "fixture-refresh-token-json", "id_token":"fixture-id-token-json", "authorization":"Bearer fixture-bearer-token"}"#
        let redacted = Redactor.redact(raw)

        XCTAssertFalse(redacted.contains("fixture-access-token-json"))
        XCTAssertFalse(redacted.contains("fixture-refresh-token-json"))
        XCTAssertFalse(redacted.contains("fixture-id-token-json"))
        XCTAssertFalse(redacted.contains("fixture-bearer-token"))
        XCTAssertEqual(
            redacted,
            #"{"access_token":"[REDACTED]","refresh_token": "[REDACTED]", "id_token":"[REDACTED]", "authorization":"[REDACTED]"}"#
        )
    }
}

private final class CountingKeyStore: SecretKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var keyData: Data?
    private var loads = 0
    private var deletes = 0

    var loadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return loads
    }

    var deleteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return deletes
    }

    func loadOrCreateKey() throws -> SymmetricKey {
        lock.lock()
        defer { lock.unlock() }
        loads += 1
        if let keyData { return SymmetricKey(data: keyData) }
        let generated = Data((0..<32).map(UInt8.init))
        keyData = generated
        return SymmetricKey(data: generated)
    }

    func deleteKey() throws {
        lock.lock()
        defer { lock.unlock() }
        deletes += 1
        keyData = nil
    }
}

private extension XCTestCase {
    func XCTAssertThrowsErrorAsync(
        _ expression: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await expression()
            XCTFail("Expected an error", file: file, line: line)
        } catch {
            // Expected.
        }
    }
}
