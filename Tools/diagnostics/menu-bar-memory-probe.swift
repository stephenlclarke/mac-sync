import AppKit
import Darwin
import SwiftUI

/// A real status item, not an NSHostingView-only test. No SyncStore, workers,
/// repository, credentials or user configuration are opened by this fixture.
@main
struct MenuBarMemoryProbe: App {
    @NSApplicationDelegateAdaptor(ProbeAppDelegate.self) private var appDelegate
    @StateObject private var state = ProbeState.shared

    var body: some Scene {
        MenuBarExtra {
            Text("Mac Sync synthetic memory check")
        } label: {
            SyncMenuBarIcon(isRunning: state.isRunning, needsAttention: state.needsAttention)
        }
    }
}

private final class ProbeAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // A command-line fixture has no launch-services window restoration.
        // Present the dashboard explicitly so animation really gets rendered.
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 420, height: 180),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Mac Sync synthetic memory check"
        window.contentView = NSHostingView(rootView: ProbeDashboard(state: .shared))
        self.window = window
        window.orderFrontRegardless()
    }
}

private struct ProbeDashboard: View {
    @ObservedObject var state: ProbeState

    var body: some View {
        VStack(spacing: 16) {
            // Exercise visible dashboard animation alongside the status item.
            SyncActivityIcon(systemName: "arrow.triangle.2.circlepath", isAnimating: state.isRunning)
                .font(.largeTitle)
            Text(state.isRunning ? "Synthetic sync in progress" : "Synthetic sync finished")
        }
        .padding(32)
    }
}

@MainActor
private final class ProbeState: ObservableObject {
    static let shared = ProbeState()
    @Published var isRunning = false
    @Published var needsAttention = false
    private let monitor = ProbeMonitor()
    private var timer: Timer?

    init() {
        setbuf(stdout, nil)
        monitor.start()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        let elapsed = monitor.heartbeat(hasWindow: NSApp.windows.contains {
            $0.title == "Mac Sync synthetic memory check" && $0.isVisible
        })
        // Exercise idle -> busy -> idle -> attention -> busy -> idle, holding
        // the busy state for most of the run, including the first transition.
        let nextRunning = elapsed >= 2 && elapsed < monitor.duration - 10
            || elapsed >= monitor.duration - 5 && elapsed < monitor.duration - 2
        let nextAttention = elapsed >= monitor.duration - 8 && elapsed < monitor.duration - 3
        if isRunning != nextRunning {
            isRunning = nextRunning
        }
        if needsAttention != nextAttention {
            needsAttention = nextAttention
        }
    }
}

/// The watchdog must not depend on the main run loop: the original defect
/// starved that loop. Exit this fixture well before it can exhaust host RAM.
private final class ProbeMonitor: @unchecked Sendable {
    let duration = max(30, Double(CommandLine.arguments.dropFirst().first ?? "120") ?? 120)
    private let started = ProcessInfo.processInfo.systemUptime
    private let lock = NSLock()
    private var lastHeartbeat = ProcessInfo.processInfo.systemUptime
    private var seenWindow = false
    private var timer: DispatchSourceTimer?
    private var warmed: UInt64?
    private var peak: UInt64 = 0
    private var warmCPU: Double = 0

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "menu-bar-probe.watchdog"))
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [self] in autoreleasepool { sample() } }
        self.timer = timer
        timer.resume()
    }

    func heartbeat(hasWindow: Bool) -> Double {
        lock.lock()
        lastHeartbeat = ProcessInfo.processInfo.systemUptime
        seenWindow = seenWindow || hasWindow
        lock.unlock()
        return ProcessInfo.processInfo.systemUptime - started
    }

    private func sample() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - started
        lock.lock()
        let stalled = now - lastHeartbeat
        let hasWindow = seenWindow
        lock.unlock()
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { fail("task_info failed: \(result)") }
        let footprint = info.phys_footprint / 1_048_576
        peak = max(peak, footprint)
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        if elapsed >= 10, warmed == nil {
            warmed = footprint
            warmCPU = cpu
        }
        if Int(elapsed) % 10 == 0 || footprint > 512 || stalled > 3 {
            print("elapsed_s=\(Int(elapsed)) footprint_mib=\(footprint) peak_mib=\(peak) heartbeat_delay_s=\(String(format: "%.2f", stalled))")
        }
        guard footprint <= 512 else { fail("512 MiB footprint budget exceeded") }
        guard stalled <= 3 else { fail("main run loop stopped responding") }
        guard elapsed < 5 || hasWindow else { fail("dashboard window was not displayed; desktop session required") }
        if let warmed, footprint > warmed + 32 {
            fail("footprint grew by more than 32 MiB after warm-up")
        }
        guard elapsed >= duration else { return }
        let cpuPercent = (cpu - warmCPU) / (elapsed - 10) * 100
        guard cpuPercent < 25 else { fail("steady CPU exceeded 25% of one core: \(cpuPercent)") }
        print("PASS duration_s=\(Int(elapsed)) warm_mib=\(warmed ?? 0) final_mib=\(footprint) peak_mib=\(peak) steady_cpu_percent=\(String(format: "%.1f", cpuPercent))")
        exit(EXIT_SUCCESS)
    }

    private func fail(_ message: String) -> Never {
        print("FAIL: \(message)")
        exit(EXIT_FAILURE)
    }
}
