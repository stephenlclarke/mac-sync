import Darwin
import Foundation

/// A watch worker handles termination between files and inside subprocess
/// waits. This lets launchd stop the observer without orphaning Git or rsync.
final class WorkerCancellation: @unchecked Sendable {
    static let shared = WorkerCancellation()
    private let lock = NSLock()
    private var cancelled = false
    private var sources: [DispatchSourceSignal] = []
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }; return cancelled
    }

    func install() {
        guard sources.isEmpty else { return }
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global(qos: .utility))
            source.setEventHandler { [self] in lock.lock(); cancelled = true; lock.unlock() }
            source.resume()
            sources.append(source)
        }
    }
}
