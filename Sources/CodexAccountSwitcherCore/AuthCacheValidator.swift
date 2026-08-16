import Foundation

public enum AuthCacheValidator {
    private static let maximumSize = 2 * 1_024 * 1_024
    private static let credentialKeys: Set<String> = [
        "access_token",
        "refresh_token",
        "id_token",
        "openai_api_key",
        "api_key",
        "tokens"
    ]

    public static func validate(_ data: Data) throws {
        guard !data.isEmpty, data.count <= maximumSize else {
            throw SwitcherError.invalidAuthenticationCache
        }
        let value = try JSONSerialization.jsonObject(with: data)
        guard let root = value as? [String: Any], !root.isEmpty else {
            throw SwitcherError.invalidAuthenticationCache
        }
        guard containsCredential(in: root) else {
            throw SwitcherError.invalidAuthenticationCache
        }
    }

    private static func containsCredential(in value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                let normalized = key.lowercased()
                if credentialKeys.contains(normalized) {
                    if let string = child as? String, !string.isEmpty { return true }
                    if let nested = child as? [String: Any], !nested.isEmpty { return true }
                }
                if containsCredential(in: child) { return true }
            }
        } else if let array = value as? [Any] {
            return array.contains(where: containsCredential(in:))
        }
        return false
    }
}
