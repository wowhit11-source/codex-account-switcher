import AppKit
import Foundation

@MainActor
public protocol OfficialAppControlling: Sendable {
    func isRunning(_ app: OfficialAppInfo) -> Bool
    func requestNormalQuit(_ app: OfficialAppInfo, timeout: TimeInterval) async -> Bool
    func forceQuit(_ app: OfficialAppInfo, userApproved: Bool) throws
    func launch(_ app: OfficialAppInfo) async throws
}

@MainActor
public final class OfficialAppController: OfficialAppControlling {
    public init() {}

    public func isRunning(_ app: OfficialAppInfo) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).isEmpty
    }

    public func requestNormalQuit(_ app: OfficialAppInfo, timeout: TimeInterval = 15) async -> Bool {
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier)
        guard !applications.isEmpty else { return true }
        applications.forEach { _ = $0.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).isEmpty {
                return true
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    public func forceQuit(_ app: OfficialAppInfo, userApproved: Bool) throws {
        guard userApproved else { throw SwitcherError.forceQuitApprovalRequired }
        NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier)
            .forEach { _ = $0.forceTerminate() }
    }

    public func launch(_ app: OfficialAppInfo) async throws {
        if isRunning(app) { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: SwitcherError.fileOperation(Redactor.redact(error.localizedDescription)))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public func open(_ app: OfficialAppInfo) async throws {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).first {
            running.activate(options: [.activateAllWindows])
            return
        }
        try await launch(app)
    }
}
