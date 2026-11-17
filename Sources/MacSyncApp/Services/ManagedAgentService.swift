import Foundation
import MacSyncCore
import ServiceManagement

enum ManagedAgentAuthorization { case enabled, requiresApproval, disabled }

protocol ManagedAgentRegistering {
    var authorization: ManagedAgentAuthorization { get }
    func register() throws
    func unregister() throws
}

struct SystemManagedAgent: ManagedAgentRegistering {
    private var service: SMAppService {
        .agent(plistName: "io.quux.mac-sync.background.plist")
    }

    var authorization: ManagedAgentAuthorization {
        switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        default: .disabled
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }
}

struct ManagedAgentService {
    let environment: [String: String]
    var service: any ManagedAgentRegistering = SystemManagedAgent()

    var configurationURL: URL {
        let support = environment["MAC_SYNC_PRIVATE_SUPPORT"] ?? "\(NSHomeDirectory())/Library/Application Support/mac-sync"
        return URL(fileURLWithPath: support).appendingPathComponent("managed-agent.json")
    }

    var errorURL: URL {
        let status = environment["MAC_SYNC_STATUS_DIR"] ?? configurationURL.deletingLastPathComponent().appendingPathComponent("status").path
        return URL(fileURLWithPath: status).appendingPathComponent("managed-agent-error.txt")
    }

    func savedSchedule() -> SyncSchedule? {
        guard let size = try? configurationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 64 * 1024,
              let data = try? Data(contentsOf: configurationURL),
              let schedule = try? JSONDecoder().decode(SyncSchedule.self, from: data), Self.isValid(schedule) else { return nil }
        return schedule
    }

    private static func isValid(_ schedule: SyncSchedule) -> Bool {
        guard SyncScheduleManager.isValid(schedule: schedule) else { return false }
        if case let .calendar(entries) = schedule {
            return entries.count <= 256
        }
        return true
    }

    func status() -> SyncScheduleStatus {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else {
            return SyncScheduleStatus(state: .disabled, agentPath: configurationURL.path)
        }
        guard let schedule = savedSchedule() else {
            return SyncScheduleStatus(state: .invalid, agentPath: configurationURL.path)
        }
        var detail: String?
        if let size = try? errorURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 16 * 1024 {
            detail = try? String(contentsOf: errorURL, encoding: .utf8)
        }
        return SyncScheduleStatus(state: .configured(schedule), agentPath: configurationURL.path,
                                  requiresApproval: service.authorization == .requiresApproval, serviceDisabled: service.authorization == .disabled, serviceDetail: detail)
    }

    func configure(schedule: SyncSchedule?) throws -> SyncScheduleStatus {
        // Disabling must remain possible even if the saved schedule is damaged.
        guard let schedule else {
            if service.authorization != .disabled { try service.unregister() }
            if FileManager.default.fileExists(atPath: configurationURL.path) { try FileManager.default.removeItem(at: configurationURL) }
            try? FileManager.default.removeItem(at: errorURL)
            return status()
        }
        if !Self.isValid(schedule) {
            throw SyncScheduleError.invalidSchedule
        }
        var previous: Data?
        if FileManager.default.fileExists(atPath: configurationURL.path) {
            guard let size = try configurationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 64 * 1024 else {
                throw SyncScheduleError.invalidSchedule
            }
            previous = try Data(contentsOf: configurationURL)
        }
        let previousError: Data?
        if let size = try? errorURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 16 * 1024 {
            previousError = try? Data(contentsOf: errorURL)
        } else { previousError = nil }
        let wasEnabled = service.authorization != .disabled
        try FileManager.default.createDirectory(at: configurationURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(schedule).write(to: configurationURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configurationURL.path)
        do {
            try? FileManager.default.removeItem(at: errorURL)
            if wasEnabled {
                try service.unregister()
            }
            try service.register()
        } catch {
            if let previousError { try? previousError.write(to: errorURL, options: .atomic) }
            if let previous {
                try? previous.write(to: configurationURL, options: .atomic)
                if wasEnabled {
                    try? service.register()
                }
            } else {
                try? FileManager.default.removeItem(at: configurationURL)
            }
            throw error
        }
        return status()
    }
}
