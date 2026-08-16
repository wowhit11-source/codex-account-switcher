import CryptoKit
import Foundation
@testable import CodexAccountSwitcherCore

final class MemoryKeyStore: SecretKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    func loadOrCreateKey() throws -> SymmetricKey {
        lock.lock()
        defer { lock.unlock() }
        if let data { return SymmetricKey(data: data) }
        let generated = Data((0..<32).map(UInt8.init))
        data = generated
        return SymmetricKey(data: generated)
    }

    func deleteKey() throws {
        lock.lock()
        data = nil
        lock.unlock()
    }
}

enum TestFixtures {
    static func temporaryDirectory(_ name: String = #function) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "CAS-Tests-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func authentication(_ label: String) -> Data {
        Data("{\"auth_mode\":\"chatgpt\",\"tokens\":{\"access_token\":\"fixture-\(label)\",\"refresh_token\":\"refresh-\(label)\"}}".utf8)
    }

    static func paths(root: URL) -> SwitcherPaths {
        SwitcherPaths(
            codexHome: root.appending(path: ".codex", directoryHint: .isDirectory),
            applicationSupport: root.appending(path: "Application Support", directoryHint: .isDirectory)
        )
    }

    static func populateSharedState(_ paths: SwitcherPaths) throws {
        try FileManager.default.createDirectory(at: paths.codexHome.appending(path: "sessions/2026/08"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.codexHome.appending(path: "skills/example"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.codexHome.appending(path: "rules"), withIntermediateDirectories: true)
        try Data("history-stable".utf8).write(to: paths.codexHome.appending(path: "history.jsonl"))
        try Data("session-stable".utf8).write(to: paths.codexHome.appending(path: "sessions/2026/08/session.jsonl"))
        try Data("config-stable".utf8).write(to: paths.codexHome.appending(path: "config.toml"))
        try Data("skill-stable".utf8).write(to: paths.codexHome.appending(path: "skills/example/SKILL.md"))
        try Data("rule-stable".utf8).write(to: paths.codexHome.appending(path: "rules/default.rules"))
    }
}
