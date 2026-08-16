import Foundation

public struct SessionMarkerMatch: Equatable, Sendable {
    public var fileURL: URL
    public var sessionID: String?

    public init(fileURL: URL, sessionID: String?) {
        self.fileURL = fileURL
        self.sessionID = sessionID
    }
}

public struct SessionMarkerFinder: Sendable {
    public let codexHome: URL

    public init(codexHome: URL) {
        self.codexHome = codexHome
    }

    public func find(marker: String) throws -> SessionMarkerMatch? {
        guard marker.hasPrefix("CAS-PROBE-"), let needle = marker.data(using: .utf8) else {
            throw SwitcherError.markerNotFound
        }
        let candidates = [
            codexHome.appending(path: "sessions", directoryHint: .isDirectory),
            codexHome.appending(path: "archived_sessions", directoryHint: .isDirectory),
            codexHome.appending(path: "history.jsonl")
        ]
        for candidate in candidates {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                guard let enumerator = FileManager.default.enumerator(
                    at: candidate,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }
                for case let file as URL in enumerator {
                    let values = try file.resourceValues(forKeys: [.isRegularFileKey])
                    guard values.isRegularFile == true, ["json", "jsonl"].contains(file.pathExtension.lowercased()) else { continue }
                    if try contains(needle: needle, in: file) {
                        return SessionMarkerMatch(fileURL: file, sessionID: inferredSessionID(from: file))
                    }
                }
            } else if try contains(needle: needle, in: candidate) {
                return SessionMarkerMatch(fileURL: candidate, sessionID: inferredSessionID(from: candidate))
            }
        }
        return nil
    }

    private func contains(needle: Data, in file: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var overlap = Data()
        while true {
            let chunk = try handle.read(upToCount: 64 * 1_024) ?? Data()
            if chunk.isEmpty { return false }
            var search = overlap
            search.append(chunk)
            if search.range(of: needle) != nil { return true }
            overlap = Data(search.suffix(max(needle.count - 1, 0)))
        }
    }

    private func inferredSessionID(from url: URL) -> String? {
        let pattern = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
        if let range = url.lastPathComponent.range(of: pattern, options: .regularExpression) {
            return String(url.lastPathComponent[range])
        }
        return nil
    }
}

public actor ContinuityTestStore {
    private let paths: SwitcherPaths
    private let writer = AtomicFileWriter()

    public init(paths: SwitcherPaths = SwitcherPaths()) {
        self.paths = paths
    }

    public func begin(sourceProfileID: UUID?, sourceAccount: String?) throws -> ContinuityTestRecord {
        let record = ContinuityTestRecord(
            sourceProfileID: sourceProfileID,
            sourceAccount: Redactor.maskEmail(sourceAccount)
        )
        try save(record)
        return record
    }

    public func load() throws -> ContinuityTestRecord? {
        guard FileManager.default.fileExists(atPath: paths.continuityRecordFile.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ContinuityTestRecord.self, from: Data(contentsOf: paths.continuityRecordFile))
    }

    public func recordMarkerMatch(_ match: SessionMarkerMatch) throws -> ContinuityTestRecord {
        guard var record = try load() else { throw SwitcherError.markerNotFound }
        record.sessionPath = match.fileURL.path
        record.sessionID = match.sessionID
        try save(record)
        return record
    }

    public func finish(
        verdict: ContinuityVerdict,
        targetProfileID: UUID?,
        targetAccount: String?,
        followUpSucceeded: Bool?,
        notes: String?
    ) throws -> ContinuityTestRecord {
        guard var record = try load() else { throw SwitcherError.markerNotFound }
        record.verdict = verdict
        record.targetProfileID = targetProfileID
        record.targetAccount = Redactor.maskEmail(targetAccount)
        record.followUpSucceeded = followUpSucceeded
        record.notes = notes.map(Redactor.redact)
        try save(record)
        return record
    }

    public func markdownReport(for record: ContinuityTestRecord) -> String {
        """
        # Session Continuity Test

        - 테스트 시작: \(record.startedAt.formatted(.iso8601))
        - 마커: \(record.marker)
        - 출발 계정: \(record.sourceAccount ?? "확인되지 않음")
        - 대상 계정: \(record.targetAccount ?? "확인되지 않음")
        - 세션 ID: \(record.sessionID ?? "확인되지 않음")
        - 로컬 세션 경로: \(record.sessionPath ?? "확인되지 않음")
        - 실제 후속 요청 성공: \(record.followUpSucceeded.map(String.init) ?? "확인되지 않음")
        - 판정: \(record.verdict.rawValue)
        - 메모: \(record.notes ?? "없음")
        """
    }

    private func save(_ record: ContinuityTestRecord) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try writer.write(try encoder.encode(record), to: paths.continuityRecordFile)
    }
}
