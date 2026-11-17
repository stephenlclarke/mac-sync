import Foundation
@testable import MacSyncApp
import XCTest

final class ManagedAgentServiceTests: XCTestCase {
    func testApprovalIsNotReportedAsRunning() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = FakeManagedAgent()
        service.authorization = .requiresApproval
        let manager = ManagedAgentService(environment: ["MAC_SYNC_PRIVATE_SUPPORT": root.path], service: service)
        let status = try manager.configure(schedule: .watch)
        XCTAssertEqual(status.schedule, .watch)
        XCTAssertTrue(status.requiresApproval)
        XCTAssertTrue(status.detail.contains("waiting for approval"))
        _ = try manager.configure(schedule: nil)
        XCTAssertEqual(manager.status().state, .disabled)
    }

    func testRegistrationFailureRestoresPreviousSchedule() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = FakeManagedAgent()
        let manager = ManagedAgentService(environment: ["MAC_SYNC_PRIVATE_SUPPORT": root.path], service: service)
        _ = try manager.configure(schedule: .interval(minutes: 60))
        let before = try Data(contentsOf: manager.configurationURL)
        service.shouldFail = true
        XCTAssertThrowsError(try manager.configure(schedule: .watch))
        XCTAssertEqual(try Data(contentsOf: manager.configurationURL), before)
        XCTAssertEqual(manager.status().schedule, .interval(minutes: 60))
    }

    func testCanDisableAnOversizedOrCorruptSchedule() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ManagedAgentService(environment: ["MAC_SYNC_PRIVATE_SUPPORT": root.path], service: FakeManagedAgent())
        try Data(repeating: 65, count: 65536).write(to: manager.configurationURL)
        XCTAssertEqual(manager.status().state, .invalid)
        XCTAssertEqual(try manager.configure(schedule: nil).state, .disabled)
    }
}

private final class FakeManagedAgent: ManagedAgentRegistering {
    var authorization = ManagedAgentAuthorization.enabled
    var shouldFail = false
    func register() throws {
        if shouldFail {
            throw NSError(domain: "test-registration", code: 1)
        }
    }

    func unregister() throws {}
}
