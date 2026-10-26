import Darwin
import Foundation
import MacSyncCore

setbuf(stdout, nil)

/// Synthetic data only. This deliberately uses the production core APIs.
func residentMiB() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? info.resident_size / 1_048_576 : 0
}

let root = FileManager.default.temporaryDirectory.appendingPathComponent("mac-sync-resource-probe-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let iterations = min(100_000, max(10, Int(CommandLine.arguments.dropFirst().first ?? "1000") ?? 1000))
print("baseline_rss_mib=\(residentMiB())")

let output = ProcessRunner().run("/usr/bin/head", ["-c", "67108864", "/dev/zero"])
precondition(output.status == 75 && output.stdout.utf8.count == 8 * 1024 * 1024)
print("64MiB_output_status=\(output.status) retained_bytes=\(output.stdout.utf8.count) rss_mib=\(residentMiB())")

let block = Data(repeating: 65, count: 64 * 1024)
let first = root.appendingPathComponent("first")
let second = root.appendingPathComponent("second")
for url in [first, second] {
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    for _ in 0 ..< 8192 {
        try handle.write(contentsOf: block)
    }
    try handle.close()
}

precondition(StreamingFileComparison.equal(first.path, second.path))
print("512MiB_comparison=equal rss_mib=\(residentMiB())")

let history = try LocalHistoryStore(directory: root.appendingPathComponent("history").path)
for run in 0 ..< 500 {
    for entry in 0 ..< 200 {
        try history.append(SyncHistoryEntry(id: "entry-\(entry)", direction: .upload, outcome: .updated,
                                            path: "file-\(entry)", source: "/source", destination: "/snapshot"), runID: "run-\(run)", ordinal: entry)
    }
    let record = SyncHistoryRecord(id: "run-\(run)", action: .sync, result: .success,
                                   timing: SyncHistoryTiming(startedAt: "start", finishedAt: "finish", durationSeconds: 1), entries: [],
                                   diagnostics: SyncHistoryDiagnostics(warningCount: 0, errorCount: 0, warnings: [], errors: []))
    try history.finish(record, entryCount: 200, ordering: Double(run))
}

let warmed = residentMiB()
for iteration in 1 ... iterations {
    try autoreleasepool {
        let page = try history.page()
        precondition(page.count == 50 && page.allSatisfy(\.entries.isEmpty))
        let entries = try history.entries(runID: page[0].id)
        precondition(entries.count == 200)
    }
    if iteration == 1 || iteration % 100 == 0 {
        print("iteration=\(iteration) rss_mib=\(residentMiB())")
    }
}

var usage = rusage()
getrusage(RUSAGE_SELF, &usage)
let peak = usage.ru_maxrss / 1_048_576
print("runs=500 entries=100000 iterations=\(iterations) warm_rss_mib=\(warmed) final_rss_mib=\(residentMiB()) peak_rss_mib=\(peak)")
precondition(peak < 128 && residentMiB() <= warmed + 32, "Synthetic memory budget exceeded")
