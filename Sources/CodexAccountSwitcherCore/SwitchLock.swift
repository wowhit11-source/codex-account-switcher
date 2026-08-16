import Darwin
import Foundation

public final class SwitchLock: @unchecked Sendable {
    private static let registry = SwitchLockRegistry()
    private let descriptor: Int32
    private let registryKey: String

    private init(descriptor: Int32, registryKey: String) {
        self.descriptor = descriptor
        self.registryKey = registryKey
    }

    deinit {
        var fileLock = flock()
        fileLock.l_type = Int16(F_UNLCK)
        fileLock.l_whence = Int16(SEEK_SET)
        _ = Darwin.fcntl(descriptor, F_SETLK, &fileLock)
        Darwin.close(descriptor)
        Self.registry.release(registryKey)
    }

    public static func acquire(at url: URL) throws -> SwitchLock {
        let registryKey = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard registry.claim(registryKey) else {
            throw SwitcherError.switchAlreadyInProgress
        }
        var keepRegistryClaim = false
        defer {
            if !keepRegistryClaim { registry.release(registryKey) }
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else {
            throw SwitcherError.fileOperation("switch lock 파일을 열 수 없습니다")
        }
        var fileLock = flock()
        fileLock.l_type = Int16(F_WRLCK)
        fileLock.l_whence = Int16(SEEK_SET)
        guard Darwin.fcntl(descriptor, F_SETLK, &fileLock) == 0 else {
            Darwin.close(descriptor)
            throw SwitcherError.switchAlreadyInProgress
        }
        _ = Darwin.fchmod(descriptor, 0o600)
        keepRegistryClaim = true
        return SwitchLock(descriptor: descriptor, registryKey: registryKey)
    }
}

private final class SwitchLockRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed: Set<String> = []

    func claim(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return claimed.insert(key).inserted
    }

    func release(_ key: String) {
        lock.lock()
        claimed.remove(key)
        lock.unlock()
    }
}
