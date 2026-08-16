import Foundation
import OSLog

public enum SecureLogger {
    private static let logger = Logger(
        subsystem: "com.yonghyunkim.CodexAccountSwitcher",
        category: "switcher"
    )

    public static func info(_ message: String) {
        logger.info("\(Redactor.redact(message), privacy: .public)")
    }

    public static func error(_ message: String) {
        logger.error("\(Redactor.redact(message), privacy: .public)")
    }
}
