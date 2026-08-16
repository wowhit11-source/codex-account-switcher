import Foundation

public enum CommandLineOperations {
    public static func emergencyRestore(paths: SwitcherPaths = SwitcherPaths()) throws {
        guard let official = OfficialAppLocator().locate() else {
            throw SwitcherError.officialAppNotFound
        }
        let running = try CodexProcessScanner().scan(officialAppPath: official.path)
        guard !running.contains(where: \.isOfficialAppProcess) else {
            throw SwitcherError.fileOperation("공식 ChatGPT/Codex 앱을 정상 종료한 뒤 다시 실행하세요")
        }
        try RecoveryStore(paths: paths).restoreLatest()
        let result = try ProcessRunner().run(
            executable: URL(fileURLWithPath: "/usr/bin/open"),
            arguments: [official.path]
        )
        guard result.exitCode == 0 else {
            throw SwitcherError.fileOperation("인증은 복구했지만 공식 앱 재실행에 실패했습니다")
        }
    }

    public static func purge(paths: SwitcherPaths = SwitcherPaths()) throws {
        if FileManager.default.fileExists(atPath: paths.applicationSupport.path) {
            try FileManager.default.removeItem(at: paths.applicationSupport)
        }
        try CryptoVault().deleteKey()
    }
}
