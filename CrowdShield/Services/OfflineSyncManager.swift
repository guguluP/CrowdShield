import Foundation
import Combine
#if canImport(Network)
import Network
#endif

enum ConnectivityStatus: String {
    case online = "Online"
    case offline = "Offline"
    case unknown = "Checking…"
}

/// Watches network reachability so the rest of the app can degrade gracefully
/// instead of silently failing when venue networks get overloaded — explicitly
/// called out as a constraint in the brief ("Network outages").
@MainActor
final class NetworkReachabilityMonitor: ObservableObject {
    @Published private(set) var status: ConnectivityStatus = .unknown

    #if canImport(Network)
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.crowdshield.reachability")
    #endif

    init() {
        #if canImport(Network)
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.status = path.status == .satisfied ? .online : .offline
            }
        }
        monitor.start(queue: queue)
        #else
        status = .online
        #endif
    }

    deinit {
        #if canImport(Network)
        monitor.cancel()
        #endif
    }
}

/// A report waiting to be synced to the command backend.
struct QueuedIncident: Identifiable {
    let id: UUID
    let report: IncidentReport
    let queuedAt: Date
    var syncAttempts: Int = 0
}

/// Buffers incident reports (and, in a full deployment, sensor readings) locally
/// when the network is unavailable, and flushes them once connectivity returns.
/// This is what lets a citizen submit a report mid-stampede even if the venue's
/// Wi-Fi/cellular is saturated — the report is never silently lost.
@MainActor
final class OfflineSyncManager: ObservableObject {
    @Published private(set) var pendingQueue: [QueuedIncident] = []
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncedAt: Date?

    private let reachability: NetworkReachabilityMonitor
    private var cancellable: AnyCancellable?
    /// Injected so callers (CrowdSimulationService) decide what "syncing" means —
    /// in this prototype that's just delivering into the in-memory service;
    /// in production this closure would POST to the backend.
    private let deliver: (IncidentReport) -> Void

    init(reachability: NetworkReachabilityMonitor, deliver: @escaping (IncidentReport) -> Void) {
        self.reachability = reachability
        self.deliver = deliver
        cancellable = reachability.$status
            .removeDuplicates()
            .sink { [weak self] status in
                if status == .online {
                    self?.flushQueue()
                }
            }
    }

    func submit(_ report: IncidentReport) {
        if reachability.status == .offline {
            pendingQueue.append(QueuedIncident(id: report.id, report: report, queuedAt: Date()))
            HapticManager.trigger(.warning)
        } else {
            deliver(report)
        }
    }

    func flushQueue() {
        guard !pendingQueue.isEmpty, !isSyncing else { return }
        isSyncing = true
        let toSync = pendingQueue
        pendingQueue.removeAll()

        // Simulated network round-trip; a real deployment awaits the actual POST.
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            for queued in toSync {
                deliver(queued.report)
            }
            await MainActor.run {
                self.isSyncing = false
                self.lastSyncedAt = Date()
            }
        }
    }

    var hasPending: Bool { !pendingQueue.isEmpty }
}
