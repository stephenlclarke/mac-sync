import CoreServices
import Darwin
import Foundation

/// Events are hints, not a list of work. Keep one dirty generation regardless
/// of event volume, and always retain the periodic full safety check.
struct WatchSyncPolicy {
    let interval: TimeInterval
    var generation: UInt64 = 1
    var completed: UInt64 = 0
    var active: UInt64?
    var firstChange: Date?
    var lastChange: Date?
    var nextCheck: Date
    var retryAfter = Date.distantPast
    var failures = 0

    init(interval: TimeInterval, now: Date) {
        self.interval = interval
        nextCheck = now
    }

    mutating func changed(now: Date) {
        generation &+= 1
        if firstChange == nil {
            firstChange = now
        }
        lastChange = now
    }

    mutating func begin(now: Date) -> Bool {
        guard active == nil, now >= retryAfter else { return false }
        let settled = lastChange.map { now.timeIntervalSince($0) >= 15 } ?? true
        let maximumWait = firstChange.map { now.timeIntervalSince($0) >= 120 } ?? false
        guard now >= nextCheck || (generation != completed && (settled || maximumWait)) else { return false }
        active = generation
        firstChange = nil
        lastChange = nil
        return true
    }

    mutating func finished(success: Bool, now: Date, deferredUntil: Date? = nil) {
        guard let active else { return }
        self.active = nil
        if success {
            completed = active
            failures = 0
            retryAfter = .distantPast
            nextCheck = now.addingTimeInterval(interval)
        } else {
            failures = min(6, failures + 1)
            retryAfter = max(deferredUntil ?? .distantPast, now.addingTimeInterval(min(interval, min(6 * 3600, 300 * pow(2, Double(failures - 1))))))
        }
    }

    var nextWake: Date? {
        guard active == nil else { return nil }
        var next = nextCheck
        if generation != completed {
            let settled = lastChange?.addingTimeInterval(15) ?? .distantPast
            let maximum = firstChange?.addingTimeInterval(120) ?? .distantFuture
            next = min(next, min(settled, maximum))
        }
        return max(next, retryAfter)
    }
}

/// An FSEvents stream uses a single serial queue. Its callback only marks work;
/// hashing, Git and file copying happen in the existing short-lived worker.
private final class FolderChangeState {
    let changed: (String?) -> Void
    private let paths: [String]
    private let controlFiles: Set<String>
    private let excluded: [String]

    init(paths: [String], controlFiles: [String], excluded: [String], changed: @escaping (String?) -> Void) {
        self.paths = paths.map(Self.normalise)
        self.controlFiles = Set(controlFiles.map(Self.normalise))
        self.excluded = excluded.map(Self.normalise)
        self.changed = changed
    }

    func matches(_ path: String) -> Bool {
        // FSEvents already supplies absolute paths. Avoid filesystem lookups
        // for every unrelated event in a watched file's parent directory.
        let path = Self.eventPath(path)
        if controlFiles.contains(path) {
            return true
        }
        if excluded.contains(where: { Self.contains($0, path) }) {
            return false
        }
        return paths.contains { Self.contains($0, path) || Self.contains(path, $0) }
    }

    private static func contains(_ root: String, _ path: String) -> Bool {
        path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
    }

    static func normalise(_ path: String) -> String {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        return eventPath(url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path)
    }

    private static func eventPath(_ path: String) -> String {
        for root in ["/private/var", "/private/tmp", "/private/etc"] where path == root || path.hasPrefix(root + "/") {
            return String(path.dropFirst("/private".count))
        }
        return path
    }
}

final class FolderChangeObservation {
    private var stream: FSEventStreamRef?
    private let state: FolderChangeState

    init(paths: [String], controlFiles: [String] = [], excluded: [String] = [], queue: DispatchQueue, changed: @escaping (String?) -> Void) throws {
        let paths = paths.flatMap { [$0, URL(fileURLWithPath: $0).resolvingSymlinksInPath().path] }
        state = FolderChangeState(paths: paths, controlFiles: controlFiles, excluded: excluded, changed: changed)
        // Watching the nearest existing parent also detects atomic replacement,
        // deleted/recreated roots and selected files that do not exist yet.
        let roots = Set((paths + controlFiles).map { path -> String in
            var directory = ObjCBool(false)
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &directory)
            var url = URL(fileURLWithPath: path)
            if !exists || !directory.boolValue || controlFiles.contains(path) {
                url.deleteLastPathComponent()
            }
            while !FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) || !directory.boolValue {
                guard url.path != "/" else { break }
                url.deleteLastPathComponent()
            }
            return FolderChangeState.normalise(url.path)
        }).sorted()
        guard !roots.isEmpty else { return }
        // The stream, not this wrapper, owns its callback state. A callback
        // already in flight cannot dereference a deinitialising observer.
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(state).toOpaque(), retain: { info in
            guard let info else { return nil }
            return UnsafeRawPointer(Unmanaged<FolderChangeState>.fromOpaque(info).retain().toOpaque())
        }, release: { info in
            if let info {
                Unmanaged<FolderChangeState>.fromOpaque(info).release()
            }
        }, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(nil, { _, info, count, rawPaths, eventFlags, _ in
            guard let info else { return }
            let observation = Unmanaged<FolderChangeState>.fromOpaque(info).takeUnretainedValue()
            let paths = rawPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
            let lost = FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagEventIdsWrapped)
            var matched: String?
            for index in 0 ..< count {
                if eventFlags[index] & lost != 0 {
                    observation.changed(nil)
                    return
                }
                let path = String(cString: paths[index])
                if observation.matches(path), matched == nil || !path.hasSuffix(".background.json") {
                    matched = path
                }
            }
            if let matched {
                observation.changed(matched)
            }
        }, &context, roots as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 3, flags) else {
            throw BackupStorageError.unavailable("macOS could not watch the selected folders. Use a timed schedule instead.")
        }
        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            stream = nil
            throw BackupStorageError.unavailable("macOS could not start folder observation. Use a timed schedule instead.")
        }
    }

    func matches(_ path: String) -> Bool {
        state.matches(path)
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}

/// One idle observer, one child at a time, and no pipe or unbounded event queue.
/// Startup always scans, so a crash/restart cannot discard pending local edits.
final class BackgroundWatchService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "tools.xyzzy.mac-sync.watch", qos: .background)
    private let stopped = DispatchSemaphore(value: 0)
    private var policy: WatchSyncPolicy
    private var observation: FolderChangeObservation?
    private var timer: DispatchSourceTimer?
    private var signals: [DispatchSourceSignal] = []
    private var child: Process?
    private var stopping = false
    private var failedAt = Date.distantFuture
    private let executable: String
    private let environment: [String: String]
    private let selection: () throws -> [String]
    private let controls: [String]
    private let excluded: [String]
    private let checkpoint: String
    private let repository: String

    init(executable: String, environment: [String: String], interval: TimeInterval, controls: [String], excluded: [String], checkpoint: String, repository: String, selection: @escaping () throws -> [String]) {
        self.executable = executable
        self.environment = environment
        self.controls = controls
        self.excluded = excluded
        self.checkpoint = checkpoint
        self.repository = repository
        self.selection = selection
        policy = WatchSyncPolicy(interval: interval, now: Date())
    }

    func run() throws {
        // All observation and process state is confined to this queue.
        try queue.sync {
            try observe()
            for number in [SIGTERM, SIGINT] {
                signal(number, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
                source.setEventHandler { [weak self] in self?.stop() }
                source.resume()
                signals.append(source)
            }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now())
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        }
        stopped.wait()
        queue.sync {
            observation = nil
            timer?.cancel()
            for source in signals {
                source.cancel()
            }
            signals.removeAll()
        }
    }

    private func observe() throws {
        let next = try FolderChangeObservation(paths: selection(), controlFiles: controls, excluded: excluded, queue: queue) { [weak self] path in
            guard let self else { return }
            let checkpointEvent = path.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path == URL(fileURLWithPath: checkpoint).resolvingSymlinksInPath().path } ?? false
            // Our worker writes its checkpoint on every run. That must not
            // schedule another run. Only an external manual recovery wakes a
            // previously failed observer through this control file.
            if checkpointEvent, child != nil {
                return
            }
            var recovered = false
            if policy.failures > 0, child == nil {
                let state = BackgroundCheckpoint.load(from: checkpoint, repository: repository)
                if let success = state.lastSuccess, success > failedAt {
                    policy.retryAfter = .distantPast
                    policy.failures = 0
                    recovered = true
                }
                if state.detail.hasPrefix("Automatic backup is paused"),
                   let preferences = preferences(),
                   preferences.pauseReason() == nil
                {
                    policy.retryAfter = .distantPast
                    policy.failures = 0
                    recovered = true
                }
            }
            if checkpointEvent, !recovered {
                return
            }
            policy.changed(now: Date())
            arm()
        }
        observation = next
    }

    private func tick() {
        defer { arm() }
        guard !stopping, policy.begin(now: Date()) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["run"]
        process.environment = environment.merging(["MAC_SYNC_WATCH_WORKER": "1"]) { _, value in value }
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finished in
            guard let self else { return }
            queue.async { [self] in
                child = nil
                if stopping {
                    stopped.signal(); return
                }
                let checkpoint = BackgroundCheckpoint.load(from: checkpoint, repository: repository)
                if finished.terminationStatus != 0 {
                    failedAt = Date()
                }
                policy.finished(success: finished.terminationReason == .exit && finished.terminationStatus == 0,
                                now: Date(), deferredUntil: checkpoint.nextAttempt)
                if let preferences = preferences(), !preferences.pauseIndefinitely,
                   let until = preferences.pausedUntil, until > Date()
                {
                    policy.retryAfter = max(until, checkpoint.nextAttempt ?? .distantPast)
                }
                do { try observe() } catch {
                    // Keep the previous stream alive. The next safety check
                    // retries selection discovery even after a config error.
                    FileHandle.standardError.write(Data("mac-sync: folder observation could not be refreshed; timed checks remain active\n".utf8))
                }
                arm()
            }
        }
        do { try process.run(); child = process }
        catch { policy.finished(success: false, now: Date()) }
    }

    private func arm() {
        guard !stopping else { return }
        if let next = policy.nextWake {
            timer?.schedule(deadline: .now() + max(0, next.timeIntervalSinceNow), leeway: .seconds(2))
        } else {
            timer?.schedule(deadline: .distantFuture)
        }
    }

    private func preferences() -> BackupPreferences? {
        guard let file = controls.first(where: { $0.hasSuffix(".preferences.json") }) else { return nil }
        return try? BackupPreferences.load(directory: (file as NSString).deletingLastPathComponent,
                                           machine: String(URL(fileURLWithPath: file).lastPathComponent.dropLast(".preferences.json".count)))
    }

    private func stop() {
        guard !stopping else { return }
        stopping = true
        timer?.cancel()
        observation = nil
        if let child {
            if kill(-child.processIdentifier, SIGTERM) != 0 {
                child.terminate()
            }
            queue.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self, let child = self.child, child.isRunning else { return }
                if kill(-child.processIdentifier, SIGKILL) != 0 {
                    kill(child.processIdentifier, SIGKILL)
                }
            }
        } else {
            stopped.signal()
        }
    }
}
