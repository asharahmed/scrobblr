import Foundation
import Network
import AppKit

/// Watches network reachability + sleep/wake. Pauses the flush loop when
/// offline or asleep; resumes on the relevant event.
@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var isOnline: Bool = true
    @Published private(set) var isAsleep: Bool = false

    private var pathMonitor: NWPathMonitor?
    private let pathQueue = DispatchQueue(label: "app.scrobblr.path")

    /// Async-stream continuations waiting on "resume". set up by
    /// `waitForResume()`. We fire and finish them as soon as the system
    /// becomes online + awake, then clear the slot so they don't leak.
    private var resumeContinuations: [UUID: CheckedContinuation<Void, Never>] = [:]

    func start() {
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            let online = (path.status == .satisfied)
            Task { @MainActor in self?.updateOnline(online) }
        }
        m.start(queue: pathQueue)
        pathMonitor = m

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(_willSleep),
                       name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(_didWake),
                       name: NSWorkspace.didWakeNotification, object: nil)
    }

    /// Explicit teardown. Called from AppCoordinator.shutdown(). Removes the
    /// NSWorkspace observers and cancels the path monitor. Defensive even
    /// though SystemMonitor currently lives for the app's full lifetime.
    func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        // Release any pending resume waiters so flush loops can exit.
        fireAllResumers()
    }

    deinit {
        // Synchronous defensive cleanup; only fires if SystemMonitor is
        // ever transient. addObserver(self) without removeObserver would
        // crash on notification delivery to a dead object.
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func updateOnline(_ online: Bool) {
        guard isOnline != online else { return }
        isOnline = online
        Log.lifecycle.info("network online=\(online, privacy: .public)")
        if isOnline && !isAsleep { fireAllResumers() }
    }

    @objc private func _willSleep() {
        // NSWorkspace selectors aren't @MainActor; trampoline to Main.
        Task { @MainActor in
            self.isAsleep = true
            Log.lifecycle.info("system willSleep")
        }
    }

    @objc private func _didWake() {
        Task { @MainActor in
            self.isAsleep = false
            Log.lifecycle.info("system didWake")
            if self.isOnline { self.fireAllResumers() }
        }
    }

    private func fireAllResumers() {
        let conts = resumeContinuations
        resumeContinuations.removeAll()
        for c in conts.values { c.resume() }
    }

    /// Suspends until the system is online AND awake. Returns immediately if
    /// already in that state. Uses a single continuation per call which is
    /// finished exactly once (no AsyncStream leakage path).
    func waitForResume() async {
        if isOnline && !isAsleep { return }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                resumeContinuations[id] = cont
            }
        } onCancel: {
            Task { @MainActor in
                if let cont = self.resumeContinuations.removeValue(forKey: id) {
                    cont.resume()
                }
            }
        }
    }
}
