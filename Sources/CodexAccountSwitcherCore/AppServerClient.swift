import Foundation

public final class AppServerConnection: @unchecked Sendable {
    private struct PendingRequest {
        let resume: @Sendable (Result<JSONValue, Error>) -> Void
        let timeout: DispatchWorkItem
    }

    private struct NotificationWaiter {
        let id: UUID
        let method: String
        let resume: @Sendable (Result<JSONValue, Error>) -> Void
        let timeout: DispatchWorkItem
    }

    private struct CachedNotification {
        let method: String
        let params: JSONValue
    }

    private let binaryURL: URL
    private let environment: [String: String]
    private let process = Process()
    private let standardInput = Pipe()
    private let standardOutput = Pipe()
    private let standardError = Pipe()
    private let lock = NSLock()
    private var receiveBuffer = Data()
    private var nextRequestID = 1
    private var pendingRequests: [Int: PendingRequest] = [:]
    private var notificationWaiters: [UUID: NotificationWaiter] = [:]
    private var recentNotifications: [CachedNotification] = []
    private var started = false
    private var stopped = false
    private var sanitizedErrorTail = ""

    public init(binaryURL: URL, codexHome: URL, extraEnvironment: [String: String] = [:]) {
        self.binaryURL = binaryURL
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = codexHome.path
        for (key, value) in extraEnvironment { environment[key] = value }
        self.environment = environment
    }

    deinit {
        stop()
    }

    public func start() async throws {
        let shouldStart: Bool = lock.withLock {
            if started { return false }
            started = true
            return true
        }
        guard shouldStart else { return }

        process.executableURL = binaryURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.environment = environment
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        standardOutput.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            self?.consume(data)
        }
        standardError.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.appendSanitizedError(text)
        }
        process.terminationHandler = { [weak self] process in
            self?.handleTermination(status: process.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            stop()
            throw SwitcherError.appServer(Redactor.redact(error.localizedDescription))
        }

        _ = try await request(
            method: "initialize",
            params: .object([
                "clientInfo": .object([
                    "name": .string("codex_account_switcher"),
                    "title": .string("Codex Account Switcher"),
                    "version": .string("1.0.2")
                ]),
                "capabilities": .object([
                    "optOutNotificationMethods": .array([
                        .string("item/agentMessage/delta"),
                        .string("item/reasoning/summaryTextDelta")
                    ])
                ])
            ]),
            timeout: 20
        )
        try send(message: .object([
            "method": .string("initialized"),
            "params": .object([:])
        ]))
    }

    public func request(method: String, params: JSONValue? = nil, timeout: TimeInterval = 20) async throws -> JSONValue {
        let requestID: Int = lock.withLock {
            defer { nextRequestID += 1 }
            return nextRequestID
        }

        return try await withCheckedThrowingContinuation { continuation in
            let timeoutWork = DispatchWorkItem { [weak self] in
                self?.timeoutRequest(requestID, method: method)
            }
            let pending = PendingRequest(
                resume: { result in continuation.resume(with: result) },
                timeout: timeoutWork
            )
            lock.withLock {
                pendingRequests[requestID] = pending
            }
            do {
                var object: [String: JSONValue] = [
                    "method": .string(method),
                    "id": .number(Double(requestID))
                ]
                if let params { object["params"] = params }
                try send(message: .object(object))
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
            } catch {
                let removed = lock.withLock { pendingRequests.removeValue(forKey: requestID) }
                removed?.timeout.cancel()
                removed?.resume(.failure(error))
            }
        }
    }

    public func waitForNotification(method: String, timeout: TimeInterval = 300) async throws -> JSONValue {
        let waiterID = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            let timeoutWork = DispatchWorkItem { [weak self] in
                self?.timeoutNotification(waiterID, method: method)
            }
            let waiter = NotificationWaiter(
                id: waiterID,
                method: method,
                resume: { result in continuation.resume(with: result) },
                timeout: timeoutWork
            )
            let cached: JSONValue? = lock.withLock {
                if let index = recentNotifications.firstIndex(where: { $0.method == method }) {
                    return recentNotifications.remove(at: index).params
                }
                notificationWaiters[waiterID] = waiter
                return nil
            }
            if let cached {
                timeoutWork.cancel()
                continuation.resume(returning: cached)
                return
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
        }
    }

    public func stop() {
        let shouldStop: Bool = lock.withLock {
            if stopped { return false }
            stopped = true
            return true
        }
        guard shouldStop else { return }
        standardOutput.fileHandleForReading.readabilityHandler = nil
        standardError.fileHandleForReading.readabilityHandler = nil
        try? standardInput.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
        }
        failAll(with: SwitcherError.appServer("연결이 종료되었습니다"))
    }

    private func send(message: JSONValue) throws {
        var data = try message.encodedData()
        data.append(0x0A)
        do {
            try standardInput.fileHandleForWriting.write(contentsOf: data)
        } catch {
            throw SwitcherError.appServer("JSON-RPC 요청을 쓰지 못했습니다")
        }
    }

    private func consume(_ data: Data) {
        let lines: [Data] = lock.withLock {
            receiveBuffer.append(data)
            var output: [Data] = []
            while let newline = receiveBuffer.firstRange(of: Data([0x0A])) {
                output.append(receiveBuffer.subdata(in: receiveBuffer.startIndex..<newline.lowerBound))
                receiveBuffer.removeSubrange(receiveBuffer.startIndex...newline.lowerBound)
            }
            return output
        }
        for line in lines where !line.isEmpty {
            handle(line: line)
        }
    }

    private func handle(line: Data) {
        guard
            let raw = try? JSONSerialization.jsonObject(with: line),
            let value = try? JSONValue(any: raw),
            let object = value.objectValue
        else { return }

        if let id = object["id"]?.intValue {
            let pending = lock.withLock { pendingRequests.removeValue(forKey: id) }
            pending?.timeout.cancel()
            guard let pending else { return }
            if let result = object["result"] {
                pending.resume(.success(result))
            } else {
                let message = object["error"]?["message"]?.stringValue ?? "알 수 없는 App Server 오류"
                pending.resume(.failure(SwitcherError.appServer(Redactor.redact(message))))
            }
            return
        }

        guard let method = object["method"]?.stringValue else { return }
        let params = object["params"] ?? .object([:])
        let matching: [NotificationWaiter] = lock.withLock {
            let values = notificationWaiters.values.filter { $0.method == method }
            for value in values { notificationWaiters.removeValue(forKey: value.id) }
            if values.isEmpty {
                recentNotifications.append(CachedNotification(method: method, params: params))
                if recentNotifications.count > 20 {
                    recentNotifications.removeFirst(recentNotifications.count - 20)
                }
            }
            return values
        }
        for waiter in matching {
            waiter.timeout.cancel()
            waiter.resume(.success(params))
        }
    }

    private func timeoutRequest(_ id: Int, method: String) {
        let pending = lock.withLock { pendingRequests.removeValue(forKey: id) }
        pending?.resume(.failure(SwitcherError.appServer("\(method) 요청 시간이 초과되었습니다")))
    }

    private func timeoutNotification(_ id: UUID, method: String) {
        let waiter = lock.withLock { notificationWaiters.removeValue(forKey: id) }
        waiter?.resume(.failure(SwitcherError.appServer("\(method) 알림 대기 시간이 초과되었습니다")))
    }

    private func appendSanitizedError(_ text: String) {
        lock.withLock {
            sanitizedErrorTail.append(Redactor.redact(text))
            if sanitizedErrorTail.count > 2_000 {
                sanitizedErrorTail = String(sanitizedErrorTail.suffix(2_000))
            }
        }
    }

    private func handleTermination(status: Int32) {
        let detail: String = lock.withLock { sanitizedErrorTail }
        let message = detail.isEmpty ? "App Server가 종료되었습니다 (\(status))" : "App Server 종료 (\(status)): \(detail)"
        failAll(with: SwitcherError.appServer(message))
    }

    private func failAll(with error: Error) {
        let pending: [PendingRequest]
        let waiters: [NotificationWaiter]
        (pending, waiters) = lock.withLock {
            let pending = Array(pendingRequests.values)
            let waiters = Array(notificationWaiters.values)
            pendingRequests.removeAll()
            notificationWaiters.removeAll()
            return (pending, waiters)
        }
        for request in pending {
            request.timeout.cancel()
            request.resume(.failure(error))
        }
        for waiter in waiters {
            waiter.timeout.cancel()
            waiter.resume(.failure(error))
        }
    }
}

public struct CodexAppServerClient: Sendable {
    public let binaryURL: URL
    public let codexHome: URL

    public init(binaryURL: URL, codexHome: URL) {
        self.binaryURL = binaryURL
        self.codexHome = codexHome
    }

    public func readAccount(refreshToken: Bool = false) async throws -> AccountIdentity? {
        let connection = AppServerConnection(binaryURL: binaryURL, codexHome: codexHome)
        try await connection.start()
        defer { connection.stop() }
        let result = try await connection.request(
            method: "account/read",
            params: .object(["refreshToken": .bool(refreshToken)])
        )
        return try Self.parseAccount(result)
    }

    public func readRateLimits() async throws -> AccountRateLimits? {
        let connection = AppServerConnection(binaryURL: binaryURL, codexHome: codexHome)
        try await connection.start()
        defer { connection.stop() }
        return try Self.parseRateLimits(try await connection.request(method: "account/rateLimits/read"))
    }

    public func readUsage() async throws -> AccountUsageSummary? {
        let connection = AppServerConnection(binaryURL: binaryURL, codexHome: codexHome)
        try await connection.start()
        defer { connection.stop() }
        let result = try await connection.request(method: "account/usage/read")
        guard let summary = result["summary"]?.objectValue else { return nil }
        return AccountUsageSummary(
            lifetimeTokens: summary["lifetimeTokens"]?.int64Value,
            peakDailyTokens: summary["peakDailyTokens"]?.int64Value,
            longestRunningTurnSeconds: summary["longestRunningTurnSec"]?.int64Value,
            currentStreakDays: summary["currentStreakDays"]?.intValue,
            longestStreakDays: summary["longestStreakDays"]?.intValue
        )
    }

    public func logout() async throws {
        let connection = AppServerConnection(binaryURL: binaryURL, codexHome: codexHome)
        try await connection.start()
        defer { connection.stop() }
        _ = try await connection.request(method: "account/logout")
    }

    public static func parseAccount(_ result: JSONValue) throws -> AccountIdentity? {
        guard let object = result.objectValue else {
            throw SwitcherError.appServer("account/read 응답 형식이 올바르지 않습니다")
        }
        guard let accountValue = object["account"] else {
            throw SwitcherError.appServer("account/read 응답에 account가 없습니다")
        }
        if accountValue == .null { return nil }
        guard let account = accountValue.objectValue, let type = account["type"]?.stringValue else {
            throw SwitcherError.appServer("account/read 계정 형식이 올바르지 않습니다")
        }
        return AccountIdentity(
            type: type,
            email: account["email"]?.stringValue,
            planType: account["planType"]?.stringValue,
            requiresOpenAIAuth: object["requiresOpenaiAuth"]?.boolValue ?? true
        )
    }

    public static func parseRateLimits(_ result: JSONValue) throws -> AccountRateLimits? {
        guard let object = result.objectValue else {
            throw SwitcherError.appServer("rateLimits 응답 형식이 올바르지 않습니다")
        }
        let rateValue = object["rateLimitsByLimitId"]?.objectValue?["codex"]
            ?? object["rateLimits"]
        guard let rateValue else { return nil }
        if rateValue == .null { return nil }
        guard let rate = rateValue.objectValue else {
            throw SwitcherError.appServer("rateLimits 본문 형식이 올바르지 않습니다")
        }
        return AccountRateLimits(
            limitID: rate["limitId"]?.stringValue,
            planType: rate["planType"]?.stringValue,
            primary: parseWindow(rate["primary"]),
            secondary: parseWindow(rate["secondary"])
        )
    }

    private static func parseWindow(_ value: JSONValue?) -> RateLimitWindow? {
        guard let object = value?.objectValue, let used = object["usedPercent"]?.doubleValue else { return nil }
        let reset = object["resetsAt"]?.doubleValue.map { Date(timeIntervalSince1970: $0) }
        return RateLimitWindow(
            usedPercent: used,
            windowDurationMinutes: object["windowDurationMins"]?.intValue,
            resetsAt: reset
        )
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
