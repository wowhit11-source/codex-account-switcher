import Foundation

public struct SwitcherPaths: Sendable {
    public let codexHome: URL
    public let applicationSupport: URL

    public init(codexHome: URL? = nil, applicationSupport: URL? = nil) {
        let environmentHome = ProcessInfo.processInfo.environment["CODEX_HOME"].map(URL.init(fileURLWithPath:))
        self.codexHome = (codexHome ?? environmentHome ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex"))
            .standardizedFileURL
        self.applicationSupport = (applicationSupport ?? FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/CodexAccountSwitcher", directoryHint: .isDirectory))
            .standardizedFileURL
    }

    public var authFile: URL { codexHome.appending(path: "auth.json") }
    public var profilesDirectory: URL { applicationSupport.appending(path: "Profiles", directoryHint: .isDirectory) }
    public var profileMetadataFile: URL { applicationSupport.appending(path: "profiles.json") }
    public var recoveryDirectory: URL { applicationSupport.appending(path: "Recovery", directoryHint: .isDirectory) }
    public var latestRecoveryFile: URL { recoveryDirectory.appending(path: "latest.recovery") }
    public var switchLockFile: URL { applicationSupport.appending(path: "switch.lock") }
    public var logDirectory: URL { applicationSupport.appending(path: "Logs", directoryHint: .isDirectory) }
    public var continuityRecordFile: URL { applicationSupport.appending(path: "continuity-test.json") }
}
