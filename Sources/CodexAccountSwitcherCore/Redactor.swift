import Foundation

public enum Redactor {
    private static let secretPatterns: [(String, String)] = [
        (#"(?i)bearer\s+[A-Za-z0-9._~+/-]+=*"#, "Bearer [REDACTED]"),
        (#"(?i)(access_token|refresh_token|id_token|authorization)\s*[=:]\s*[^\s,}\"]+"#, "$1=[REDACTED]"),
        (#"sk-[A-Za-z0-9_-]{8,}"#, "[REDACTED_API_KEY]"),
        (#"eyJ[A-Za-z0-9._-]{12,}"#, "[REDACTED_JWT]")
    ]

    public static func maskEmail(_ email: String?) -> String? {
        guard let email, let at = email.firstIndex(of: "@") else { return email }
        let local = email[..<at]
        let domain = email[at...]
        guard let first = local.first else { return "***\(domain)" }
        return "\(first)***\(domain)"
    }

    public static func redact(_ input: String) -> String {
        var output = input
        for (pattern, replacement) in secretPatterns {
            output = replacing(pattern: pattern, in: output, with: replacement)
        }
        output = replacing(
            pattern: #"([A-Za-z0-9._%+-])[A-Za-z0-9._%+-]*(@[A-Za-z0-9.-]+\.[A-Za-z]{2,})"#,
            in: output,
            with: "$1***$2"
        )
        return output
    }

    public static func containsSecretLikeValue(_ input: String) -> Bool {
        secretPatterns.contains { pattern, _ in
            input.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func replacing(pattern: String, in input: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return input }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return expression.stringByReplacingMatches(in: input, range: range, withTemplate: replacement)
    }
}
