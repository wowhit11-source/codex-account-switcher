import Darwin
import Foundation

public protocol CodexProcessScanning: Sendable {
    func scan(officialAppPath: String?) throws -> [ProcessSummary]
}

extension CodexProcessScanner: CodexProcessScanning {}

public enum ProcessTerminationSignal: Equatable, Sendable {
    case interrupt
    case terminate

    fileprivate var rawValue: Int32 {
        switch self {
        case .interrupt: SIGINT
        case .terminate: SIGTERM
        }
    }
}

public protocol ProcessSignaling: Sendable {
    func send(_ signal: ProcessTerminationSignal, to pid: Int32) throws
}

public struct DarwinProcessSignalSender: ProcessSignaling {
    public init() {}

    public func send(_ signal: ProcessTerminationSignal, to pid: Int32) throws {
        guard pid > 1 else {
            throw SwitcherError.fileOperation("안전하지 않은 프로세스 ID는 종료할 수 없습니다: \(pid)")
        }
        guard Darwin.kill(pid, signal.rawValue) == 0 else {
            if errno == ESRCH { return }
            throw SwitcherError.fileOperation("Codex CLI 프로세스에 정상 종료를 요청하지 못했습니다: pid=\(pid)")
        }
    }
}

public struct CodexProcessController: Sendable {
    private let scanner: any CodexProcessScanning
    private let signalSender: any ProcessSignaling

    public init(
        scanner: any CodexProcessScanning = CodexProcessScanner(),
        signalSender: any ProcessSignaling = DarwinProcessSignalSender()
    ) {
        self.scanner = scanner
        self.signalSender = signalSender
    }

    public func closeConflictingProcesses(
        officialAppPath: String?,
        interruptGracePeriod: Duration = .seconds(1),
        terminationTimeout: Duration = .seconds(5),
        pollInterval: Duration = .milliseconds(250)
    ) async throws {
        var blockers = try currentBlockers(officialAppPath: officialAppPath)
        guard !blockers.isEmpty else { return }

        try send(.interrupt, to: blockers)
        if interruptGracePeriod > .zero {
            try await Task.sleep(for: interruptGracePeriod)
        }

        blockers = try currentBlockers(officialAppPath: officialAppPath)
        guard !blockers.isEmpty else { return }
        try send(.terminate, to: blockers)

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: terminationTimeout)
        while true {
            blockers = try currentBlockers(officialAppPath: officialAppPath)
            if blockers.isEmpty { return }
            guard clock.now < deadline else {
                throw SwitcherError.activeProcessTerminationFailed(blockers.map(\.safeDescription))
            }
            if pollInterval > .zero {
                try await Task.sleep(for: pollInterval)
            }
            // A wrapper can exit before its native Codex child. Rescanning exposes
            // that child as the new logical root, so request normal termination again.
            try send(.terminate, to: blockers)
        }
    }

    private func currentBlockers(officialAppPath: String?) throws -> [ProcessSummary] {
        try scanner.scan(officialAppPath: officialAppPath).filter(\.blocksSwitch)
    }

    private func send(_ signal: ProcessTerminationSignal, to blockers: [ProcessSummary]) throws {
        for blocker in blockers {
            try signalSender.send(signal, to: blocker.pid)
        }
    }
}
