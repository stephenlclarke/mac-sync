import Foundation

@MainActor
final class LocalRepairController: ObservableObject {
    @Published private(set) var receipts: [String] = []
    @Published private(set) var message: String?
    @Published private(set) var isRunning = false
    private var task: Task<Void, Never>?
    private var generation = 0
    private let planner: any OnDeviceRepairPlanning

    init(planner: any OnDeviceRepairPlanning = OnDeviceDiagnosisService.shared) {
        self.planner = planner
    }

    func start(runtime: any LocalRepairRuntime, finished: @escaping @MainActor () -> Void) {
        guard !isRunning else { return }
        generation += 1
        let expected = generation
        receipts = []
        message = nil
        isRunning = true
        task = Task {
            do {
                try await LocalRepairSession.run(runtime: runtime, planner: planner) { receipts.append($0) }
            } catch is CancellationError {
                // Verified earlier repairs are retained; no remaining action is started.
            } catch {
                if generation == expected {
                    message = error.localizedDescription
                }
            }
            guard generation == expected, !Task.isCancelled else { return }
            isRunning = false
            task = nil
            finished()
        }
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        isRunning = false
        message = "Stopped. Earlier verified repairs are retained. No further actions will run."
    }
}
