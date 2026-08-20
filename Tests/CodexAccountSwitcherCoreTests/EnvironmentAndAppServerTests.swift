import Foundation
import XCTest
@testable import CodexAccountSwitcherCore

final class EnvironmentAndAppServerTests: XCTestCase {
    func testOfficialAppDetectionUsesBundleMetadataAndBundledCodex() throws {
        let root = try TestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appending(path: "Unexpected Name.app", directoryHint: .isDirectory)
        let contents = app.appending(path: "Contents")
        let resources = contents.appending(path: "Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.openai.codex",
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "42"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: contents.appending(path: "Info.plist"))
        let binary = resources.appending(path: "codex")
        FileManager.default.createFile(atPath: binary.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

        let located = OfficialAppLocator(searchRoots: [root]).inspect(appURL: app)
        XCTAssertEqual(located?.bundleIdentifier, "com.openai.codex")
        XCTAssertEqual(located?.bundledCodexPath, binary.path)
    }

    func testProcessScannerBlocksStandaloneCLIButNotOfficialAppChildren() {
        let sample = """
        100 1 /Applications/ChatGPT.app/Contents/MacOS/ChatGPT
        101 100 /Applications/ChatGPT.app/Contents/Resources/codex app-server
        200 1 /opt/homebrew/bin/codex resume abc
        """
        let results = CodexProcessScanner().parse(output: sample, officialAppPath: "/Applications/ChatGPT.app")
        XCTAssertEqual(results.filter(\.blocksSwitch).map(\.pid), [200])
        XCTAssertEqual(results.filter(\.isOfficialAppProcess).map(\.pid), [100, 101])
    }

    func testProcessScannerDetectsHostManagedOfficialAppAuthentication() {
        let sample = """
        100 1 /Applications/ChatGPT.app/Contents/MacOS/ChatGPT
        101 100 /Applications/ChatGPT.app/Contents/Resources/codex -c features.code_mode_host=true app-server --analytics-default-enabled
        """
        let scanner = CodexProcessScanner()
        let results = scanner.parse(output: sample, officialAppPath: "/Applications/ChatGPT.app")

        XCTAssertEqual(results.filter(\.usesHostManagedAuthentication).map(\.pid), [101])
        XCTAssertEqual(scanner.officialAppAuthenticationMode(in: results), .hostManaged)
    }

    func testProcessScannerDoesNotAssumeHostManagedAuthenticationForStandardAppServer() {
        let sample = """
        100 1 /Applications/ChatGPT.app/Contents/MacOS/ChatGPT
        101 100 /Applications/ChatGPT.app/Contents/Resources/codex app-server
        """
        let scanner = CodexProcessScanner()
        let results = scanner.parse(output: sample, officialAppPath: "/Applications/ChatGPT.app")

        XCTAssertFalse(results.contains(where: \.usesHostManagedAuthentication))
        XCTAssertEqual(scanner.officialAppAuthenticationMode(in: results), .standardOrUnknown)
    }

    func testProcessScannerIgnoresComputerUseHelpersAndCollapsesCLIProcessTree() {
        let sample = """
        191 50 /Users/test/.codex/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient computer-history mcp
        300 20 node /Users/test/.bun/bin/codex --dangerously-bypass-approvals-and-sandbox resume thread-id
        301 300 /opt/homebrew/lib/node_modules/@openai/codex/vendor/bin/codex --dangerously-bypass-approvals-and-sandbox resume thread-id
        302 301 /opt/homebrew/lib/node_modules/@openai/codex/vendor/bin/codex-code-mode-host
        """
        let results = CodexProcessScanner().parse(output: sample, officialAppPath: "/Applications/ChatGPT.app")

        XCTAssertEqual(results.filter(\.blocksSwitch).map(\.pid), [300])
        XCTAssertEqual(results.filter(\.blocksSwitch).map(\.safeDescription), ["pid=300 codex"])
        XCTAssertFalse(results.contains(where: { $0.pid == 191 }))
        XCTAssertFalse(results.contains(where: { $0.pid == 301 }))
        XCTAssertFalse(results.contains(where: { $0.pid == 302 }))
    }

    func testProcessScannerDoesNotTreatAppNameBeginningWithCodexAsCLI() {
        let sample = """
        400 1 /tmp/Codex Utility.app/Contents/MacOS/Utility --background
        """
        let results = CodexProcessScanner().parse(output: sample, officialAppPath: "/Applications/ChatGPT.app")

        XCTAssertTrue(results.isEmpty)
    }

    func testProcessScannerKeepsIndependentCLIProcessTrees() {
        let sample = """
        500 20 /opt/homebrew/bin/codex resume first
        600 30 node /Users/test/.bun/bin/codex resume second
        601 600 /opt/homebrew/lib/node_modules/@openai/codex/vendor/bin/codex resume second
        """
        let results = CodexProcessScanner().parse(output: sample, officialAppPath: "/Applications/ChatGPT.app")

        XCTAssertEqual(results.filter(\.blocksSwitch).map(\.pid), [500, 600])
    }

    func testActiveProcessConflictExplainsOpenButPossiblyIdleCLI() {
        let message = SwitcherError.activeProcessConflict(["pid=500 codex", "pid=600 codex"]).errorDescription

        XCTAssertTrue(message?.contains("2개가 열린 상태") == true)
        XCTAssertTrue(message?.contains("작업 중이 아니어도") == true)
        XCTAssertTrue(message?.contains("exit 또는 Ctrl+C") == true)
    }

    func testOneClickAvailabilityAllowsVerifiedHostManagedButRejectsKeyringAuthentication() {
        let hostManaged = AccountSwitchPreflightPolicy.evaluate(
            credentialsStoreSetting: "file",
            authFileExists: true,
            officialAppAuthenticationMode: .hostManaged,
            runtimeIdentityAvailable: true
        )
        let keyring = AccountSwitchPreflightPolicy.evaluate(
            credentialsStoreSetting: "keyring",
            authFileExists: true,
            officialAppAuthenticationMode: .standardOrUnknown,
            runtimeIdentityAvailable: true
        )

        XCTAssertTrue(hostManaged.isAvailable)
        XCTAssertNil(hostManaged.reason)
        XCTAssertTrue(hostManaged.warning?.contains("호환 모드") == true)
        XCTAssertFalse(keyring.isAvailable)
        XCTAssertTrue(keyring.reason?.contains("keyring") == true)
    }

    func testOneClickAvailabilityAllowsVerifiedAutoOrUnspecifiedFileAuthentication() {
        for setting in ["auto", nil] as [String?] {
            let availability = AccountSwitchPreflightPolicy.evaluate(
                credentialsStoreSetting: setting,
                authFileExists: true,
                officialAppAuthenticationMode: .notRunning,
                runtimeIdentityAvailable: true
            )
            XCTAssertTrue(availability.isAvailable)
        }

        let unverified = AccountSwitchPreflightPolicy.evaluate(
            credentialsStoreSetting: nil,
            authFileExists: true,
            officialAppAuthenticationMode: .notRunning,
            runtimeIdentityAvailable: false
        )
        XCTAssertFalse(unverified.isAvailable)
    }

    func testAccountSwitchPreflightAllowsRuntimeVerifiedUnspecifiedFileAuthentication() async throws {
        let root = try TestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = TestFixtures.paths(root: root)
        try TestFixtures.populateSharedState(paths)
        try AtomicFileWriter().write(TestFixtures.authentication("verified"), to: paths.authFile)
        let preflight = AccountSwitchPreflight(
            paths: paths,
            officialApp: Self.testOfficialApp,
            processScanner: StaticAuthenticationProcessScanner(),
            accountProbe: StaticAuthenticationProbe(identity: Self.testIdentity)
        )

        try await preflight.validateBeforeSwitch()
    }

    func testAccountSwitchPreflightRejectsConfiguredKeyring() async throws {
        let root = try TestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = TestFixtures.paths(root: root)
        try TestFixtures.populateSharedState(paths)
        try Data("cli_auth_credentials_store = \"keyring\"\n".utf8)
            .write(to: paths.codexHome.appending(path: "config.toml"))
        try AtomicFileWriter().write(TestFixtures.authentication("keyring"), to: paths.authFile)
        let preflight = AccountSwitchPreflight(
            paths: paths,
            officialApp: Self.testOfficialApp,
            processScanner: StaticAuthenticationProcessScanner(),
            accountProbe: StaticAuthenticationProbe(identity: Self.testIdentity)
        )

        do {
            try await preflight.validateBeforeSwitch()
            XCTFail("keyring 설정은 파일 기반 원클릭 전환을 허용하면 안 됩니다")
        } catch SwitcherError.oneClickSwitchUnavailable(let reason) {
            XCTAssertTrue(reason.contains("keyring"))
        }
    }

    func testAccountSwitchPreflightAllowsVerifiedHostManagedAppBeforeAndAfterLaunch() async throws {
        let root = try TestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = TestFixtures.paths(root: root)
        try TestFixtures.populateSharedState(paths)
        try AtomicFileWriter().write(TestFixtures.authentication("host-managed"), to: paths.authFile)
        let hostManaged = ProcessSummary(
            pid: 101,
            parentPID: 100,
            executable: Self.testOfficialApp.bundledCodexPath ?? "codex",
            isOfficialAppProcess: true,
            blocksSwitch: false,
            usesHostManagedAuthentication: true
        )
        let preflight = AccountSwitchPreflight(
            paths: paths,
            officialApp: Self.testOfficialApp,
            processScanner: StaticAuthenticationProcessScanner(processes: [hostManaged]),
            accountProbe: StaticAuthenticationProbe(identity: Self.testIdentity)
        )

        for validation in [preflight.validateBeforeSwitch, preflight.validateAfterLaunch] {
            try await validation()
        }
    }

    func testOfficialLogoutScriptTargetsOfficialBundleAndLocalizedMenuItems() {
        let script = OfficialAppAccountController.logoutScript(bundleIdentifier: "com.openai.codex")

        XCTAssertTrue(script.contains("bundle identifier is \"com.openai.codex\""))
        XCTAssertTrue(script.contains("\"Log Out\""))
        XCTAssertTrue(script.contains("\"Sign Out\""))
        XCTAssertTrue(script.contains("\"로그아웃\""))
        XCTAssertTrue(script.contains("click menu item"))
    }

    func testOfficialLogoutPermissionFailureProvidesRecoveryPath() {
        let message = OfficialAppAccountController.failureMessage(
            errorNumber: -1743,
            message: "Not authorized"
        )

        XCTAssertTrue(message.contains("자동화 권한"))
        XCTAssertTrue(message.contains("개인정보 보호 및 보안"))
        XCTAssertTrue(message.contains("System Events"))
    }

    func testProcessControllerInterruptsWrapperThenTerminatesExposedNativeChild() async throws {
        let wrapper = ProcessSummary(
            pid: 300,
            parentPID: 20,
            executable: "/Users/test/.bun/bin/codex",
            isOfficialAppProcess: false,
            blocksSwitch: true
        )
        let native = ProcessSummary(
            pid: 301,
            parentPID: 1,
            executable: "/opt/homebrew/bin/codex",
            isOfficialAppProcess: false,
            blocksSwitch: true
        )
        let state = FakeProcessControlState(
            blockers: [wrapper],
            replacementAfterInterrupt: native,
            clearsOnTerminate: true
        )
        let controller = CodexProcessController(
            scanner: FakeProcessScanner(state: state),
            signalSender: FakeProcessSignalSender(state: state)
        )

        try await controller.closeConflictingProcesses(
            officialAppPath: "/Applications/ChatGPT.app",
            interruptGracePeriod: .zero,
            terminationTimeout: .zero,
            pollInterval: .zero
        )

        XCTAssertEqual(
            state.recordedSignals(),
            [RecordedProcessSignal(signal: .interrupt, pid: 300), RecordedProcessSignal(signal: .terminate, pid: 301)]
        )
        XCTAssertTrue(state.currentBlockers().isEmpty)
    }

    func testProcessControllerDoesNotForceKillAProcessThatRefusesNormalTermination() async {
        let blocker = ProcessSummary(
            pid: 500,
            parentPID: 20,
            executable: "/opt/homebrew/bin/codex",
            isOfficialAppProcess: false,
            blocksSwitch: true
        )
        let state = FakeProcessControlState(
            blockers: [blocker],
            replacementAfterInterrupt: nil,
            clearsOnTerminate: false
        )
        let controller = CodexProcessController(
            scanner: FakeProcessScanner(state: state),
            signalSender: FakeProcessSignalSender(state: state)
        )

        do {
            try await controller.closeConflictingProcesses(
                officialAppPath: "/Applications/ChatGPT.app",
                interruptGracePeriod: .zero,
                terminationTimeout: .zero,
                pollInterval: .zero
            )
            XCTFail("정상 종료를 거부한 프로세스에서는 실패해야 합니다")
        } catch SwitcherError.activeProcessTerminationFailed(let remaining) {
            XCTAssertEqual(remaining, ["pid=500 codex"])
        } catch {
            XCTFail("예상하지 못한 오류: \(error)")
        }

        XCTAssertEqual(
            state.recordedSignals(),
            [RecordedProcessSignal(signal: .interrupt, pid: 500), RecordedProcessSignal(signal: .terminate, pid: 500)]
        )
    }

    func testProcessRunnerCapturesOutput() throws {
        let result = try ProcessRunner().run(
            executable: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["runner-ok"]
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.output, "runner-ok")
    }

    func testAccountAndRateLimitResponseParsing() throws {
        let account: JSONValue = .object([
            "account": .object([
                "type": .string("chatgpt"),
                "email": .string("user@example.com"),
                "planType": .string("pro")
            ]),
            "requiresOpenaiAuth": .bool(true)
        ])
        XCTAssertEqual(
            try CodexAppServerClient.parseAccount(account),
            AccountIdentity(type: "chatgpt", email: "user@example.com", planType: "pro", requiresOpenAIAuth: true)
        )

        let rates: JSONValue = .object([
            "rateLimits": .object([
                "limitId": .string("codex"),
                "planType": .string("pro"),
                "primary": .object([
                    "usedPercent": .number(74),
                    "windowDurationMins": .number(1_008),
                    "resetsAt": .number(1_800_000_000)
                ]),
                "secondary": .null
            ])
        ])
        let parsed = try CodexAppServerClient.parseRateLimits(rates)
        XCTAssertEqual(parsed?.primary?.usedPercent, 74)
        XCTAssertEqual(parsed?.primary?.windowDurationMinutes, 1_008)
        XCTAssertEqual(parsed?.primary?.remainingPercent, 26)
    }

    func testRateLimitParsingPrefersCodexMultiBucketAndClampsRemainingPercent() throws {
        let rates: JSONValue = .object([
            "rateLimits": .object([
                "limitId": .string("legacy"),
                "primary": .object(["usedPercent": .number(90)])
            ]),
            "rateLimitsByLimitId": .object([
                "codex": .object([
                    "limitId": .string("codex"),
                    "planType": .string("pro"),
                    "primary": .object([
                        "usedPercent": .number(25),
                        "windowDurationMins": .number(300),
                        "resetsAt": .number(1_800_000_000)
                    ]),
                    "secondary": .object([
                        "usedPercent": .number(110),
                        "windowDurationMins": .number(10_080)
                    ])
                ]),
                "codex_other": .object([
                    "limitId": .string("codex_other"),
                    "primary": .object(["usedPercent": .number(42)])
                ])
            ])
        ])

        let parsed = try XCTUnwrap(CodexAppServerClient.parseRateLimits(rates))
        XCTAssertEqual(parsed.limitID, "codex")
        XCTAssertEqual(parsed.primary?.remainingPercent, 75)
        XCTAssertEqual(parsed.primary?.windowDurationMinutes, 300)
        XCTAssertEqual(parsed.secondary?.remainingPercent, 0)

        let underflow = RateLimitWindow(usedPercent: -12, windowDurationMinutes: nil, resetsAt: nil)
        XCTAssertEqual(underflow.remainingPercent, 100)
    }

    private static let testOfficialApp = OfficialAppInfo(
        path: "/Applications/Codex.app",
        bundleIdentifier: "com.openai.codex",
        shortVersion: "test",
        buildVersion: "test",
        bundledCodexPath: "/Applications/Codex.app/Contents/Resources/codex"
    )

    private static let testIdentity = AccountIdentity(
        type: "chatgpt",
        email: "user@example.com",
        planType: "pro",
        requiresOpenAIAuth: true
    )
}

private struct StaticAuthenticationProcessScanner: CodexProcessScanning {
    var processes: [ProcessSummary] = []

    func scan(officialAppPath: String?) throws -> [ProcessSummary] {
        processes
    }
}

private struct StaticAuthenticationProbe: AccountProbing {
    var identity: AccountIdentity?

    func readAccount(refreshToken: Bool) async throws -> AccountIdentity? {
        identity
    }

    func readRateLimits() async throws -> AccountRateLimits? {
        nil
    }
}

private struct RecordedProcessSignal: Equatable, Sendable {
    var signal: ProcessTerminationSignal
    var pid: Int32
}

private final class FakeProcessControlState: @unchecked Sendable {
    private let lock = NSLock()
    private var blockers: [ProcessSummary]
    private var signals: [RecordedProcessSignal] = []
    private let replacementAfterInterrupt: ProcessSummary?
    private let clearsOnTerminate: Bool

    init(
        blockers: [ProcessSummary],
        replacementAfterInterrupt: ProcessSummary?,
        clearsOnTerminate: Bool
    ) {
        self.blockers = blockers
        self.replacementAfterInterrupt = replacementAfterInterrupt
        self.clearsOnTerminate = clearsOnTerminate
    }

    func scan() -> [ProcessSummary] {
        lock.lock()
        defer { lock.unlock() }
        return blockers
    }

    func record(_ signal: ProcessTerminationSignal, pid: Int32) {
        lock.lock()
        defer { lock.unlock() }
        signals.append(RecordedProcessSignal(signal: signal, pid: pid))
        switch signal {
        case .interrupt:
            if let replacementAfterInterrupt {
                blockers = [replacementAfterInterrupt]
            }
        case .terminate:
            if clearsOnTerminate {
                blockers = []
            }
        }
    }

    func recordedSignals() -> [RecordedProcessSignal] {
        lock.lock()
        defer { lock.unlock() }
        return signals
    }

    func currentBlockers() -> [ProcessSummary] {
        scan()
    }
}

private struct FakeProcessScanner: CodexProcessScanning {
    let state: FakeProcessControlState

    func scan(officialAppPath: String?) throws -> [ProcessSummary] {
        state.scan()
    }
}

private struct FakeProcessSignalSender: ProcessSignaling {
    let state: FakeProcessControlState

    func send(_ signal: ProcessTerminationSignal, to pid: Int32) throws {
        state.record(signal, pid: pid)
    }
}
