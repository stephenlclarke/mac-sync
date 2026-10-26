import Darwin
import Foundation

/// Watches atomic status replacements. There is no repeating scan timer.
final class LocalStateObservation {
    private let source: DispatchSourceFileSystemObject
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue(label: "tools.xyzzy.mac-sync.state", qos: .background)

    init?(directory: String, changed: @escaping @Sendable () -> Void) {
        var observed = URL(fileURLWithPath: directory)
        while !FileManager.default.fileExists(atPath: observed.path), observed.path != "/" {
            observed.deleteLastPathComponent()
        }
        let descriptor = open(observed.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: queue)
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

    deinit { pending?.cancel(); source.cancel() }
}
