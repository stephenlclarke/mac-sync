import Foundation
import IOKit.ps
import Network

public struct BackupPreferences: Codable, Equatable, Sendable {
    public var pausedUntil: Date?
    public var pauseIndefinitely = false
    public var waitForACPower = false
    public var avoidExpensiveNetworks = false
    public var allowLowPowerMode = false
    public var incomingPolicy = IncomingSyncPolicy.automatic

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case pausedUntil, pauseIndefinitely, waitForACPower, avoidExpensiveNetworks, allowLowPowerMode, incomingPolicy
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        pausedUntil = try values.decodeIfPresent(Date.self, forKey: .pausedUntil)
        pauseIndefinitely = try values.decodeIfPresent(Bool.self, forKey: .pauseIndefinitely) ?? false
        waitForACPower = try values.decodeIfPresent(Bool.self, forKey: .waitForACPower) ?? false
        avoidExpensiveNetworks = try values.decodeIfPresent(Bool.self, forKey: .avoidExpensiveNetworks) ?? false
        allowLowPowerMode = try values.decodeIfPresent(Bool.self, forKey: .allowLowPowerMode) ?? false
        incomingPolicy = try values.decodeIfPresent(IncomingSyncPolicy.self, forKey: .incomingPolicy) ?? .automatic
    }

    public func pauseReason(now: Date = Date()) -> String? {
        if pauseIndefinitely {
            return "Automatic backup is paused until you resume it"
        }
        if let pausedUntil, pausedUntil > now {
            return "Automatic backup is paused until \(pausedUntil.formatted())"
        }
        return nil
    }

    public static func url(directory: String, machine: String) -> URL {
        URL(fileURLWithPath: directory).appendingPathComponent("\(machine).preferences.json")
    }

    public static func load(directory: String, machine: String) throws -> Self {
        let url = url(directory: directory, machine: machine)
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 16 * 1024 else {
            throw BackupStorageError.unavailable("Backup preferences could not be read. Review and save them again in Settings.")
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    public func save(directory: String, machine: String) throws {
        let url = Self.url(directory: directory, machine: machine)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func resourceDeferral(cloudFolder: Bool) -> String? {
        if let reason = pauseReason() {
            return reason
        }
        if waitForACPower, let sources = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let source = IOPSGetProvidingPowerSourceType(sources)?.takeUnretainedValue(),
           source as String != kIOPSACPowerValue
        {
            return "Waiting for external power"
        }
        // A provider's own uploader is outside this app's control. This option
        // only limits Git transfers initiated by Mac Sync itself.
        if !cloudFolder, avoidExpensiveNetworks {
            let monitor = NWPathMonitor()
            let state = NetworkCostState()
            let ready = DispatchSemaphore(value: 0)
            monitor.pathUpdateHandler = { path in
                state.set(expensive: path.isExpensive || path.isConstrained)
                ready.signal()
            }
            monitor.start(queue: DispatchQueue(label: "tools.xyzzy.mac-sync.network-cost", qos: .utility))
            let known = ready.wait(timeout: .now() + 2) == .success
            monitor.cancel()
            if !known {
                return "Waiting to check the network connection"
            }
            if state.expensive {
                return "Waiting for an unmetered network connection"
            }
        }
        return nil
    }
}

private final class NetworkCostState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var expensive: Bool {
        lock.lock(); defer { lock.unlock() }; return value
    }

    func set(expensive: Bool) {
        lock.lock(); value = expensive; lock.unlock()
    }
}

public enum BackupProtectionResult: String, Codable, Sendable {
    case uploaded, savedToFolder, localOnly
}

public struct BackupProtectionRecord: Codable, Equatable, Sendable {
    public let destination: String
    public let result: BackupProtectionResult
    public let commit: String
    public let savedAt: Date
    public let verifiedGitAt: Date?
    public let savedToFolderAt: Date?

    public init(destination: String, result: BackupProtectionResult, commit: String, previous: Self? = nil, now: Date = Date()) {
        self.destination = destination
        self.result = result
        self.commit = commit
        savedAt = now
        verifiedGitAt = result == .uploaded ? now : (previous?.destination == destination ? previous?.verifiedGitAt : nil)
        savedToFolderAt = result == .savedToFolder ? now : (previous?.destination == destination ? previous?.savedToFolderAt : nil)
    }

    public static func load(directory: String, machine: String) -> Self? {
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(machine).protection.json")
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 16 * 1024,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    public func save(directory: String, machine: String) throws {
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(machine).protection.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
