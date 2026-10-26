import CryptoKit
import Darwin
import Foundation

/// File size never determines the amount of comparison memory allocated.
public enum StreamingFileComparison {
    public static func equal(_ left: String, _ right: String) -> Bool {
        guard let lhs = try? FileHandle(forReadingFrom: URL(fileURLWithPath: left)) else { return false }
        defer { try? lhs.close() }
        guard let rhs = try? FileHandle(forReadingFrom: URL(fileURLWithPath: right)) else { return false }
        defer { try? rhs.close() }
        var leftStat = stat()
        var rightStat = stat()
        if fstat(lhs.fileDescriptor, &leftStat) == 0, fstat(rhs.fileDescriptor, &rightStat) == 0,
           leftStat.st_size != rightStat.st_size
        {
            return false
        }
        do {
            while true {
                let comparison = try autoreleasepool { () -> (equal: Bool, ended: Bool) in
                    let a = try lhs.read(upToCount: 64 * 1024) ?? Data()
                    let b = try rhs.read(upToCount: 64 * 1024) ?? Data()
                    return (a == b, a.isEmpty)
                }
                if !comparison.equal {
                    return false
                }
                if comparison.ended {
                    return true
                }
            }
        } catch { return false }
    }
}

public enum StreamingFileFingerprint {
    public static func sha256(_ path: String) throws -> String {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        var hash = SHA256()
        while try autoreleasepool(invoking: {
            guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { return false }
            hash.update(data: chunk)
            return true
        }) {}
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// One producer drains the pipe; the consumer receives bounded complete lines.
final class ProcessOutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var overflow = false
    private var cancelled = false
    private let limit: Int
    private let lineHandler: ((String) -> Void)?

    init(limit: Int, lineHandler: ((String) -> Void)?) {
        self.limit = max(1, limit)
        self.lineHandler = lineHandler
    }

    func drain(_ handle: FileHandle, standardError: Bool) {
        defer { try? handle.close() }
        var pending = Data()
        let descriptor = handle.fileDescriptor
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        var bytes = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            lock.lock()
            let stopped = cancelled
            lock.unlock()
            if stopped {
                return
            }
            var event = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&event, 1, 200)
            if ready < 0, errno == EINTR {
                continue
            }
            if ready < 0 {
                markOverflow(); return
            }
            if ready == 0 {
                continue
            }
            let count = Darwin.read(descriptor, &bytes, bytes.count)
            if count < 0, errno == EAGAIN || errno == EINTR {
                continue
            }
            if count < 0 {
                markOverflow(); return
            }
            if count == 0 {
                break
            }
            let chunk = Data(bytes.prefix(count))
            if !standardError, let lineHandler {
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 10) {
                    lineHandler(String(decoding: pending[..<newline], as: UTF8.self))
                    pending.removeSubrange(...newline)
                }
                if pending.count > 256 * 1024 {
                    markOverflow()
                    pending.removeAll(keepingCapacity: false)
                }
            } else {
                lock.lock()
                if standardError {
                    let available = max(0, limit - stderr.count)
                    stderr.append(chunk.prefix(available))
                    overflow = overflow || chunk.count > available
                } else {
                    let available = max(0, limit - stdout.count)
                    stdout.append(chunk.prefix(available))
                    overflow = overflow || chunk.count > available
                }
                lock.unlock()
            }
        }
        if !pending.isEmpty {
            lineHandler?(String(decoding: pending, as: UTF8.self))
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    private func markOverflow() {
        lock.lock()
        overflow = true
        lock.unlock()
    }

    func result(status: Int32) -> CommandResult {
        lock.lock()
        defer { lock.unlock() }
        return CommandResult(
            status: status == 0 && overflow ? 75 : status,
            stdout: String(decoding: stdout, as: UTF8.self),
            stderr: String(decoding: stderr, as: UTF8.self)
                + (overflow ? "\nCommand output exceeded its safe capture limit or could not be read.\n" : ""),
        )
    }
}
