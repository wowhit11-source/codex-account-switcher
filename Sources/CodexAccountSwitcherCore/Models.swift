import Foundation

public struct AccountProfile: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var displayName: String
    public var maskedEmail: String?
    public var planType: String?
    public var createdAt: Date
    public var lastValidatedAt: Date?
    public var isActive: Bool

    public init(
        id: UUID = UUID(),
        displayName: String,
        maskedEmail: String? = nil,
        planType: String? = nil,
        createdAt: Date = Date(),
        lastValidatedAt: Date? = nil,
        isActive: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.maskedEmail = maskedEmail
        self.planType = planType
        self.createdAt = createdAt
        self.lastValidatedAt = lastValidatedAt
        self.isActive = isActive
    }
}

public struct AccountIdentity: Codable, Equatable, Sendable {
    public var type: String
    public var email: String?
    public var planType: String?
    public var requiresOpenAIAuth: Bool

    public init(type: String, email: String?, planType: String?, requiresOpenAIAuth: Bool) {
        self.type = type
        self.email = email
        self.planType = planType
        self.requiresOpenAIAuth = requiresOpenAIAuth
    }
}

public struct RateLimitWindow: Codable, Equatable, Sendable {
    public var usedPercent: Double
    public var windowDurationMinutes: Int?
    public var resetsAt: Date?

    public init(usedPercent: Double, windowDurationMinutes: Int?, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.windowDurationMinutes = windowDurationMinutes
        self.resetsAt = resetsAt
    }
}

public struct AccountRateLimits: Codable, Equatable, Sendable {
    public var limitID: String?
    public var planType: String?
    public var primary: RateLimitWindow?
    public var secondary: RateLimitWindow?

    public init(limitID: String?, planType: String?, primary: RateLimitWindow?, secondary: RateLimitWindow?) {
        self.limitID = limitID
        self.planType = planType
        self.primary = primary
        self.secondary = secondary
    }
}

public struct AccountUsageSummary: Codable, Equatable, Sendable {
    public var lifetimeTokens: Int64?
    public var peakDailyTokens: Int64?
    public var longestRunningTurnSeconds: Int64?
    public var currentStreakDays: Int?
    public var longestStreakDays: Int?

    public init(
        lifetimeTokens: Int64? = nil,
        peakDailyTokens: Int64? = nil,
        longestRunningTurnSeconds: Int64? = nil,
        currentStreakDays: Int? = nil,
        longestStreakDays: Int? = nil
    ) {
        self.lifetimeTokens = lifetimeTokens
        self.peakDailyTokens = peakDailyTokens
        self.longestRunningTurnSeconds = longestRunningTurnSeconds
        self.currentStreakDays = currentStreakDays
        self.longestStreakDays = longestStreakDays
    }
}

public struct ProfileSecret: Codable, Equatable, Sendable {
    public var authCache: Data
    public var accountEmail: String?
    public var planType: String?
    public var capturedAt: Date

    public init(authCache: Data, accountEmail: String?, planType: String?, capturedAt: Date = Date()) {
        self.authCache = authCache
        self.accountEmail = accountEmail
        self.planType = planType
        self.capturedAt = capturedAt
    }
}

public enum SwitchPhase: String, Codable, Sendable, CaseIterable {
    case idle
    case checkingProcesses
    case closingConflictingProcesses
    case checkingAuthenticationSource
    case snapshottingSessions
    case savingCurrentAccount
    case quittingOfficialApp
    case backingUpAuthentication
    case replacingAuthentication
    case validatingAccount
    case verifyingAuthenticationIsolation
    case relaunchingOfficialApp
    case verifyingSessionProtection
    case rollingBack
    case completed
}

public struct SwitchResult: Equatable, Sendable {
    public var account: AccountIdentity
    public var snapshotChanges: SnapshotComparison
    public var rateLimits: AccountRateLimits?

    public init(account: AccountIdentity, snapshotChanges: SnapshotComparison, rateLimits: AccountRateLimits?) {
        self.account = account
        self.snapshotChanges = snapshotChanges
        self.rateLimits = rateLimits
    }
}

public enum ContinuityVerdict: String, Codable, Sendable, CaseIterable {
    case pending = "PENDING"
    case pass = "PASS"
    case partial = "PARTIAL"
    case fail = "FAIL"
}

public struct ContinuityTestRecord: Codable, Equatable, Sendable {
    public var marker: String
    public var startedAt: Date
    public var sourceProfileID: UUID?
    public var targetProfileID: UUID?
    public var sessionPath: String?
    public var sessionID: String?
    public var sourceAccount: String?
    public var targetAccount: String?
    public var followUpSucceeded: Bool?
    public var verdict: ContinuityVerdict
    public var notes: String?

    public init(
        marker: String = "CAS-PROBE-\(UUID().uuidString)",
        startedAt: Date = Date(),
        sourceProfileID: UUID? = nil,
        targetProfileID: UUID? = nil,
        sessionPath: String? = nil,
        sessionID: String? = nil,
        sourceAccount: String? = nil,
        targetAccount: String? = nil,
        followUpSucceeded: Bool? = nil,
        verdict: ContinuityVerdict = .pending,
        notes: String? = nil
    ) {
        self.marker = marker
        self.startedAt = startedAt
        self.sourceProfileID = sourceProfileID
        self.targetProfileID = targetProfileID
        self.sessionPath = sessionPath
        self.sessionID = sessionID
        self.sourceAccount = sourceAccount
        self.targetAccount = targetAccount
        self.followUpSucceeded = followUpSucceeded
        self.verdict = verdict
        self.notes = notes
    }
}
