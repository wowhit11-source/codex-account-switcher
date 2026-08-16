import CryptoKit
import Foundation
import Security

public protocol SecretKeyStore: Sendable {
    func loadOrCreateKey() throws -> SymmetricKey
    func deleteKey() throws
}

public struct SystemKeychainStore: SecretKeyStore, Sendable {
    public let service: String
    public let account: String

    public init(
        service: String = "com.yonghyunkim.CodexAccountSwitcher",
        account: String = "profile-encryption-key-v1"
    ) {
        self.service = service
        self.account = account
    }

    public func loadOrCreateKey() throws -> SymmetricKey {
        if let existing = try loadKeyData() {
            guard existing.count == 32 else {
                throw SwitcherError.keychain("저장된 키 길이가 올바르지 않습니다")
            }
            return SymmetricKey(data: existing)
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw SwitcherError.keychain("보안 난수 생성 실패")
        }
        let data = Data(bytes)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem, let existing = try loadKeyData() {
            return SymmetricKey(data: existing)
        }
        guard status == errSecSuccess else {
            throw SwitcherError.keychain("키 저장 실패 (OSStatus \(status))")
        }
        return SymmetricKey(data: data)
    }

    public func deleteKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SwitcherError.keychain("키 삭제 실패 (OSStatus \(status))")
        }
    }

    private func loadKeyData() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw SwitcherError.keychain("키 읽기 실패 (OSStatus \(status))")
        }
        return data
    }
}

/// Keeps the profile encryption key in memory for the lifetime of the menu bar
/// process. The Keychain remains the source of truth; this only prevents every
/// encrypt/decrypt operation in one account switch from asking macOS for the
/// same item again.
public final class ProcessCachedSecretKeyStore: SecretKeyStore, @unchecked Sendable {
    public static let shared = ProcessCachedSecretKeyStore(backing: SystemKeychainStore())

    private let backing: any SecretKeyStore
    private let lock = NSLock()
    private var cachedKeyData: Data?

    public init(backing: any SecretKeyStore) {
        self.backing = backing
    }

    public func loadOrCreateKey() throws -> SymmetricKey {
        lock.lock()
        defer { lock.unlock() }

        if let cachedKeyData {
            return SymmetricKey(data: cachedKeyData)
        }

        let key = try backing.loadOrCreateKey()
        let keyData = key.withUnsafeBytes { Data($0) }
        guard keyData.count == 32 else {
            throw SwitcherError.keychain("캐시할 암호화 키 길이가 올바르지 않습니다")
        }
        cachedKeyData = keyData
        return key
    }

    public func deleteKey() throws {
        lock.lock()
        defer { lock.unlock() }

        try backing.deleteKey()
        cachedKeyData = nil
    }
}
