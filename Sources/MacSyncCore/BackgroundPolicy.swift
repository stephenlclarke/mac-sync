import Darwin
import Foundation

public struct BackgroundCheckpoint: Codable, Equatable {
    public var consecutiveFailures = 0
    public var nextAttempt: Date?
    public var lastInventory: Date?
    public var lastSecrets: Date?
    public var lastSuccess: Date?
    public var detail = "Waiting for the next scheduled sync"

    public init() {}

    public static func load(from path: String) -> BackgroundCheckpoint {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              (attributes[.size] as? NSNumber)?.intValue ?? Int.max < 64 * 1024,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let state = try? JSONDecoder().decode(Self.self, from: data)
        else { return Self() }
        return state
    }

    public func save(to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    public mutating func failed(now: Date = Date(), authentication: Bool) {
        consecutiveFailures += 1
        let delay = authentication ? 12 * 3600.0 : min(6 * 3600.0, 900 * pow(2, Double(min(6, consecutiveFailures - 1))))
        nextAttempt = now.addingTimeInterval(delay)
        detail = authentication ? "GitHub credentials need attention; background retries are paused" : "Waiting to retry GitHub connectivity"
    }
}

/// No permanent monitor: the source exists only for the lifetime of a worker.
final class BackgroundResources: @unchecked Sendable {
    private let lock = NSLock()
    private var memoryPressure = false
    private let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical, .normal], queue: .global(qos: .background))

    init() {
        source.setEventHandler { [weak self] in
            guard let self else { return }
            lock.lock()
            memoryPressure = !source.data.contains(.normal)
            lock.unlock()
        }
        source.resume()
    }

    deinit { source.cancel() }

    var deferralReason: String? {
        lock.lock()
        let pressured = memoryPressure
        lock.unlock()
        if pressured {
            return "Waiting for memory pressure to ease"
        }
        if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical {
            return "Waiting for this Mac to cool down"
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return "Waiting while Low Power Mode is enabled"
        }
        return nil
    }
}
