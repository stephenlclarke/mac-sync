import Darwin
import Foundation
@testable import MacSyncApp
import MacSyncCore
import XCTest

final class LocalWorkerInspectionTests: XCTestCase {
    func testReleasedPersistentLockIsIdleWithoutRemovingOrChangingItsEmptyFile() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let lock = try XCTUnwrap(MacSyncProcessLock.acquire(at: fixture.pidFile))
        lock.release()
        XCTAssertEqual(try Data(contentsOf: fixture.pidFile), Data())
        for _ in 0 ..< 10 {
            XCTAssertEqual(try fixture.worker(), .idle)
        }
        XCTAssertEqual(try Data(contentsOf: fixture.pidFile), Data())
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: fixture.pidFile.deletingLastPathComponent().path),
            ["pid"]
        )
    }

    func testKernelLockDetectsActiveWorkerEvenWithEmptyOrStalePIDText() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let executable = try buildLockHolder(in: fixture.root)
        for contents in [Data(), Data("stale PID text is not lock ownership".utf8)] {
            try contents.write(to: fixture.pidFile)
            let child = try LockHolder(executable: executable, path: fixture.pidFile)
            for _ in 0 ..< 10 {
                XCTAssertEqual(try fixture.worker(), .active)
            }
            XCTAssertTrue(child.process.isRunning)
            XCTAssertEqual(try Data(contentsOf: fixture.pidFile), contents)
            child.stop()
            XCTAssertEqual(try fixture.worker(), .idle)
            XCTAssertEqual(try Data(contentsOf: fixture.pidFile), contents)
        }
    }

    func testLockInspectionFailsClosedForLinksAndNonRegularFilesWithoutCreatingMissingPaths() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        XCTAssertEqual(try fixture.worker(), .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.pidFile.path))
        let target = fixture.root.appendingPathComponent("target")
        try Data().write(to: target)
        try FileManager.default.createSymbolicLink(at: fixture.pidFile, withDestinationURL: target)
        XCTAssertEqual(try fixture.worker(), .unknown)
        XCTAssertEqual(try Data(contentsOf: target), Data())
        try FileManager.default.removeItem(at: fixture.pidFile)
        XCTAssertEqual(mkfifo(fixture.pidFile.path, 0o600), 0)
        XCTAssertEqual(try fixture.worker(), .unknown)
    }

    private func buildLockHolder(in root: URL) throws -> URL {
        // A separate process is essential: POSIX F_GETLK does not report the
        // querying process's own record locks. Match the production F_SETLK contract.
        let source = root.appendingPathComponent("lock-holder.c")
        try """
        #include <fcntl.h>
        #include <unistd.h>
        int main(int argc, char **argv) {
            if (argc != 2) return 2;
            alarm(10);
            int fd = open(argv[1], O_RDWR);
            if (fd < 0) return 3;
            struct flock lock = { .l_type = F_WRLCK, .l_whence = SEEK_SET };
            if (fcntl(fd, F_SETLK, &lock) < 0) return 4;
            if (write(STDOUT_FILENO, "r", 1) != 1) return 5;
            char end;
            (void)read(STDIN_FILENO, &end, 1);
            return close(fd) == 0 ? 0 : 6;
        }
        """.write(to: source, atomically: true, encoding: .utf8)
        let executable = root.appendingPathComponent("lock-holder")
        let result = ProcessRunner().run(
            "/usr/bin/cc",
            [source.path, "-o", executable.path],
            timeout: 15,
            outputLimit: 4096
        )
        guard result.status == 0 else {
            throw NSError(domain: "LocalWorkerInspectionTests", code: Int(result.status),
                          userInfo: [NSLocalizedDescriptionKey: result.stderr])
        }
        return executable
    }
}

private struct Fixture {
    let root: URL
    let pidFile: URL
    let configuration: SyncConfiguration

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        pidFile = root.appendingPathComponent("mac-sync-fixture.lock/pid")
        configuration = SyncConfiguration(
            homeDirectory: root.path,
            dataRepository: root.appendingPathComponent("data").path,
            statusDirectory: root.appendingPathComponent("status").path,
            machineName: "fixture",
            pathsFile: root.appendingPathComponent("paths").path
        )
        try FileManager.default.createDirectory(
            at: pidFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    func worker() throws -> LocalWorkerState {
        try LocalRepairInspectionReader.worker(configuration: configuration, temporaryDirectory: root.path)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class LockHolder {
    let process = Process()
    private let input = Pipe()
    private var stopped = false

    init(executable: URL, path: URL) throws {
        let output = Pipe()
        process.executableURL = executable
        process.arguments = [path.path]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        guard try output.fileHandleForReading.read(upToCount: 1) == Data("r".utf8) else {
            stop()
            throw NSError(domain: "LocalWorkerInspectionTests", code: 1)
        }
        try output.fileHandleForReading.close()
    }

    deinit { stop() }

    func stop() {
        guard !stopped else { return }
        stopped = true
        try? input.fileHandleForWriting.close()
        process.waitUntilExit()
    }
}
