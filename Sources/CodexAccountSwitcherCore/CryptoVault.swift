import CryptoKit
import Foundation

public struct CryptoVault: Sendable {
    private struct Envelope: Codable {
        let version: Int
        let sealedCombined: Data
        let createdAt: Date
    }

    private let keyStore: any SecretKeyStore

    public init(keyStore: any SecretKeyStore = ProcessCachedSecretKeyStore.shared) {
        self.keyStore = keyStore
    }

    public func encrypt(_ plaintext: Data) throws -> Data {
        do {
            let key = try keyStore.loadOrCreateKey()
            let sealed = try AES.GCM.seal(plaintext, using: key)
            guard let combined = sealed.combined else {
                throw SwitcherError.cryptography("AES-GCM 봉인 데이터를 만들지 못했습니다")
            }
            let envelope = Envelope(version: 1, sealedCombined: combined, createdAt: Date())
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(envelope)
        } catch let error as SwitcherError {
            throw error
        } catch {
            throw SwitcherError.cryptography(Redactor.redact(error.localizedDescription))
        }
    }

    public func decrypt(_ encrypted: Data) throws -> Data {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let envelope = try decoder.decode(Envelope.self, from: encrypted)
            guard envelope.version == 1 else {
                throw SwitcherError.cryptography("지원하지 않는 암호문 버전")
            }
            let box = try AES.GCM.SealedBox(combined: envelope.sealedCombined)
            return try AES.GCM.open(box, using: keyStore.loadOrCreateKey())
        } catch let error as SwitcherError {
            throw error
        } catch {
            throw SwitcherError.cryptography(Redactor.redact(error.localizedDescription))
        }
    }

    public func deleteKey() throws {
        try keyStore.deleteKey()
    }
}
