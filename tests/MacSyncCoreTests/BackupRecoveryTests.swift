import Foundation
@testable import MacSyncCore
import XCTest

final class BackupRecoveryTests: XCTestCase {
    func testOlderRevisionCanBeRestoredExportedAndUndone() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        try fixture.write("old version", to: fixture.source)
        XCTAssertEqual(fixture.run(["sync"]), 0)
        let service = BackupRecoveryService(repository: fixture.repository.path, statusDirectory: fixture.status.path,
                                            home: fixture.home.path, environment: fixture.environment)
        let older = try XCTUnwrap(service.revisions(machine: "target").first)
        try fixture.write("new version", to: fixture.source)
        XCTAssertEqual(fixture.run(["sync"]), 0)
        try fixture.write("unsaved local edit", to: fixture.source)
        XCTAssertEqual(fixture.run(["restore", "--from", "target", "--revision", older.id, "--path", ".tool", "--force"]), 0)
        XCTAssertEqual(try String(contentsOf: fixture.source, encoding: .utf8), "old version")
        let undo = try XCTUnwrap(service.undoRecords().first)
        XCTAssertEqual(fixture.run(["undo-restore", undo.id, "--preview"]), 0)
        XCTAssertEqual(try String(contentsOf: fixture.source, encoding: .utf8), "old version")
        XCTAssertEqual(fixture.run(["undo-restore", undo.id, "--force"]), 0)
        XCTAssertEqual(try String(contentsOf: fixture.source, encoding: .utf8), "unsaved local edit")
        let output = fixture.root.appendingPathComponent("export")
        XCTAssertEqual(fixture.run(["restore", "--from", "target", "--revision", older.id, "--path", ".tool", "--output", output.path]), 0)
        XCTAssertEqual(try String(contentsOf: output.appendingPathComponent("home/.tool"), encoding: .utf8), "old version")
        XCTAssertEqual(try String(contentsOf: fixture.source, encoding: .utf8), "unsaved local edit")
    }

    func testRecoveryVerificationDoesNotReplaceLocalFilesOrSwitchTheBranch() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        try fixture.write("backup", to: fixture.source)
        XCTAssertEqual(fixture.run(["sync"]), 0)
        try fixture.write("leave this untouched", to: fixture.source)
        let service = BackupRecoveryService(repository: fixture.repository.path, statusDirectory: fixture.status.path,
                                            home: fixture.home.path, environment: fixture.environment)
        let revision = try XCTUnwrap(service.revisions(machine: "target").first)
        XCTAssertEqual(fixture.run(["versions", "--from", "target", "--offset", "0"]), 0)
        XCTAssertEqual(fixture.run(["verify", "--from", "target", "--revision", revision.id]), 0)
        let report = try service.testRecovery(machine: "target", revision: revision.id)
        XCTAssertGreaterThanOrEqual(report.verifiedFiles, 2)
        XCTAssertEqual(try String(contentsOf: fixture.source, encoding: .utf8), "leave this untouched")
        let branch = ProcessRunner(environment: fixture.environment).run("git", ["-C", fixture.repository.path, "branch", "--show-current"])
        XCTAssertEqual(branch.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "main")
        XCTAssertThrowsError(try service.workspace(machine: "../escape", revision: revision.id))
        XCTAssertThrowsError(try service.workspace(machine: "target", revision: "--exec=bad"))
    }

    func testPausePreferencesAndProtectionRecordsRemainHonest() throws {
        let fixture = try BackupFixture()
        defer { fixture.remove() }
        var preferences = BackupPreferences()
        let now = Date(timeIntervalSince1970: 1000)
        preferences.pausedUntil = now.addingTimeInterval(3600)
        XCTAssertNotNil(preferences.pauseReason(now: now))
        XCTAssertNil(preferences.pauseReason(now: now.addingTimeInterval(3601)))
        preferences.pauseIndefinitely = true
        preferences.waitForACPower = true
        try preferences.save(directory: fixture.status.path, machine: "target")
        XCTAssertEqual(try BackupPreferences.load(directory: fixture.status.path, machine: "target"), preferences)
        let uploaded = BackupProtectionRecord(destination: "git:first", result: .uploaded, commit: "first", now: now)
        let pending = BackupProtectionRecord(destination: "git:first", result: .localOnly, commit: "second", previous: uploaded)
        XCTAssertEqual(pending.verifiedGitAt, now)
        let folder = BackupProtectionRecord(destination: "folder:second", result: .savedToFolder, commit: "second", previous: uploaded)
        XCTAssertNil(folder.verifiedGitAt)
        XCTAssertNotNil(folder.savedToFolderAt)
        try folder.save(directory: fixture.status.path, machine: "target")
        XCTAssertEqual(BackupProtectionRecord.load(directory: fixture.status.path, machine: "target"), folder)
    }
}
