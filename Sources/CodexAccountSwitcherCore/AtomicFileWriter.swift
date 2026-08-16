import Darwin
import Foundation

public struct AtomicFileWriter: Sendable {
    public init() {}

    public func write(_ data: Data, to destination: URL, mode: mode_t = 0o600) throws {
        let fileManager = FileManager.default
        let directory = destination.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let temporary = directory.appending(path: ".\(destination.lastPathComponent).cas-\(UUID().uuidString).tmp")
        let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, mode)
        guard descriptor >= 0 else {
            throw SwitcherError.fileOperation("임시 파일을 만들 수 없습니다 (errno \(errno))")
        }

        var shouldUnlink = true
        defer {
            Darwin.close(descriptor)
            if shouldUnlink {
                Darwin.unlink(temporary.path)
            }
        }

        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let written = Darwin.write(descriptor, base.advanced(by: offset), rawBuffer.count - offset)
                guard written > 0 else {
                    throw SwitcherError.fileOperation("임시 파일 쓰기에 실패했습니다 (errno \(errno))")
                }
                offset += written
            }
        }

        guard Darwin.fsync(descriptor) == 0 else {
            throw SwitcherError.fileOperation("임시 파일 fsync에 실패했습니다 (errno \(errno))")
        }
        guard Darwin.fchmod(descriptor, mode) == 0 else {
            throw SwitcherError.fileOperation("파일 권한 설정에 실패했습니다 (errno \(errno))")
        }
        guard Darwin.rename(temporary.path, destination.path) == 0 else {
            throw SwitcherError.fileOperation("원자적 rename에 실패했습니다 (errno \(errno))")
        }
        shouldUnlink = false

        guard Darwin.chmod(destination.path, mode) == 0 else {
            throw SwitcherError.fileOperation("최종 파일 권한 설정에 실패했습니다 (errno \(errno))")
        }

        let directoryDescriptor = Darwin.open(directory.path, O_RDONLY)
        if directoryDescriptor >= 0 {
            _ = Darwin.fsync(directoryDescriptor)
            Darwin.close(directoryDescriptor)
        }
    }

    public func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}

public enum SecureTemporaryFile {
    public static func removeBestEffort(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let descriptor = Darwin.open(url.path, O_WRONLY)
        if descriptor >= 0 {
            var info = stat()
            if Darwin.fstat(descriptor, &info) == 0, info.st_size > 0 {
                let zeroes = [UInt8](repeating: 0, count: 4_096)
                var remaining = Int(info.st_size)
                _ = Darwin.lseek(descriptor, 0, SEEK_SET)
                while remaining > 0 {
                    let count = min(remaining, zeroes.count)
                    let wrote = zeroes.withUnsafeBytes { buffer in
                        Darwin.write(descriptor, buffer.baseAddress, count)
                    }
                    guard wrote > 0 else { break }
                    remaining -= wrote
                }
                _ = Darwin.fsync(descriptor)
            }
            Darwin.close(descriptor)
        }
        _ = Darwin.unlink(url.path)
    }
}
