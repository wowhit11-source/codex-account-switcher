import Foundation

public struct ProcessResult: Equatable, Sendable {
    public var exitCode: Int32
    public var output: String

    public init(exitCode: Int32, output: String) {
        self.exitCode = exitCode
        self.output = output
    }
}

public struct ProcessRunner: Sendable {
    public init() {}

    public func run(
        executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        redactOutput: Bool = true
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        process.currentDirectoryURL = currentDirectory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            throw SwitcherError.fileOperation("프로세스를 시작하지 못했습니다: \(Redactor.redact(error.localizedDescription))")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        var output = String(data: data, encoding: .utf8) ?? ""
        if redactOutput { output = Redactor.redact(output) }
        return ProcessResult(exitCode: process.terminationStatus, output: output)
    }
}
