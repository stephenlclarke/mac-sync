import Darwin
import Foundation

/// Watches atomic status replacements. There is no repeating scan timer.
final class LocalStateObservation {
    private let source: DispatchSourceFileSystemObject
    private let directory: String
    private let observedPath: String
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue(label: "tools.xyzzy.mac-sync.state", qos: .background)

    init?(directory: String, changed: @escaping @Sendable () -> Void) {
        self.directory = directory
        var observed = URL(fileURLWithPath: directory)
        while !FileManager.default.fileExists(atPath: observed.path), observed.path != "/" {
            observed.deleteLastPathComponent()
        }
        let descriptor = open(observed.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        observedPath = observed.path
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )
        source.setCancelHandler { close(descriptor) }
        source.setEventHandler { [weak self] in
            guard let self else { return }
            pending?.cancel()
            let work = DispatchWorkItem(block: changed)
            pending = work
            queue.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
        source.resume()
    }

    /// A replaced directory can leave a valid descriptor watching the old inode.
    var isHealthy: Bool {
        guard !source.isCancelled else { return false }
        var expected = URL(fileURLWithPath: directory)
        while !FileManager.default.fileExists(atPath: expected.path), expected.path != "/" {
            expected.deleteLastPathComponent()
        }
        guard expected.path == observedPath else { return false }
        var opened = stat()
        var current = stat()
        return fstat(source.handle, &opened) == 0 && stat(observedPath, &current) == 0
            && opened.st_dev == current.st_dev && opened.st_ino == current.st_ino
    }

    deinit { pending?.cancel(); source.cancel() }
}
