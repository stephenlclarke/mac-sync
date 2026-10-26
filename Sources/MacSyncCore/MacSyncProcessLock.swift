import Darwin
import Foundation

public enum MacSyncProcessIdentity {
    /// PID files can survive a crash and PIDs can be reused. Never treat an
    /// arbitrary live PID, zero or a process-group selector as our worker.
    public static func isWorker(_ pid: Int32, environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        guard pid > 1, kill(pid, 0) == 0 else { return false }
        let result = ProcessRunner(environment: environment).run("/bin/ps", ["-p", String(pid), "-o", "comm="], timeout: 2, outputLimit: 4096)
        guard result.status == 0 else { return false }
        return URL(fileURLWithPath: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)).lastPathComponent == "mac-sync"
    }
}

/// An advisory process lock whose ownership is released automatically when the
/// process exits, including after a crash.
public final class MacSyncProcessLock: @unchecked Sendable {
    public let url: URL
    public let ownerProcessID: Int32

    private var descriptor: Int32
    private let registryKey: String
    private static let registry = ProcessLockRegistry()

    private init(
        url: URL,
        ownerProcessID: Int32,
        descriptor: Int32,
        registryKey: String,
    ) {
        self.url = url
        self.ownerProcessID = ownerProcessID
        self.descriptor = descriptor
        self.registryKey = registryKey
    }

    deinit {
        release()
    }

    public static func userInterfaceLockURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> URL {
        temporaryDirectory(environment: environment)
            .appendingPathComponent("mac-sync-ui.lock")
    }

    public static func syncServiceLockURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> URL {
        temporaryDirectory(environment: environment)
            .appendingPathComponent("mac-sync-service.lock")
    }

    public static func acquire(
        at url: URL,
        ownerProcessID: Int32 = getpid(),
        fileManager: FileManager = .default,
    ) throws -> MacSyncProcessLock? {
        let url = url.standardizedFileURL
        let registryKey = url.path
        guard registry.reserve(registryKey) else { return nil }

        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700],
            )

            let descriptor = Darwin.open(
                url.path,
                O_RDWR | O_CREAT | O_CLOEXEC,
                S_IRUSR | S_IWUSR,
            )
            guard descriptor >= 0 else {
                throw posixError(operation: "open", path: url.path)
            }

            guard setLock(descriptor: descriptor, type: F_WRLCK) == 0 else {
                let lockError = errno
                Darwin.close(descriptor)
                if lockError == EACCES || lockError == EAGAIN {
                    registry.release(registryKey)
                    return nil
                }
                throw posixError(operation: "fcntl", path: url.path, code: lockError)
            }

            do {
                guard Darwin.fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
                    throw posixError(operation: "fchmod", path: url.path)
                }
                try writeOwnerProcessID(ownerProcessID, to: descriptor, path: url.path)
                return MacSyncProcessLock(
                    url: url,
                    ownerProcessID: ownerProcessID,
                    descriptor: descriptor,
                    registryKey: registryKey,
                )
            } catch {
                _ = setLock(descriptor: descriptor, type: F_UNLCK)
                _ = Darwin.close(descriptor)
                throw error
            }
        } catch {
            registry.release(registryKey)
            throw error
        }
    }

    public func release() {
        guard descriptor >= 0 else { return }
        _ = Darwin.ftruncate(descriptor, 0)
        _ = Self.setLock(descriptor: descriptor, type: F_UNLCK)
        _ = Darwin.close(descriptor)
        descriptor = -1
        Self.registry.release(registryKey)
    }

    private static func temporaryDirectory(environment: [String: String]) -> URL {
        URL(
            fileURLWithPath: environment["TMPDIR"] ?? NSTemporaryDirectory(),
            isDirectory: true,
        )
    }

    private static func writeOwnerProcessID(
        _ processID: Int32,
        to descriptor: Int32,
        path: String,
    ) throws {
        guard Darwin.ftruncate(descriptor, 0) == 0 else {
            throw posixError(operation: "ftruncate", path: path)
        }
        guard Darwin.lseek(descriptor, 0, SEEK_SET) >= 0 else {
            throw posixError(operation: "lseek", path: path)
        }

        let data = Data("\(processID)\n".utf8)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(
                    descriptor,
                    bytes.baseAddress?.advanced(by: offset),
                    bytes.count - offset,
                )
                if written < 0 {
                    if errno == EINTR {
                        continue
                    }
                    throw posixError(operation: "write", path: path)
                }
                offset += written
            }
        }
    }

    private static func setLock(descriptor: Int32, type: Int32) -> Int32 {
        var lock = flock()
        lock.l_type = Int16(type)
        lock.l_whence = Int16(SEEK_SET)
        return Darwin.fcntl(descriptor, F_SETLK, &lock)
    }

    private static func posixError(
        operation: String,
        path: String,
        code: Int32 = errno,
    ) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [
                NSLocalizedDescriptionKey:
                    "\(operation) failed for \(path): \(String(cString: strerror(code)))",
            ],
        )
    }
}

private final class ProcessLockRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var paths = Set<String>()

    func reserve(_ path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return paths.insert(path).inserted
    }

    func release(_ path: String) {
        lock.lock()
        paths.remove(path)
        lock.unlock()
    }
}
