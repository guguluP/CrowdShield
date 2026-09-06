import Foundation
import Combine

/// A single real-time push received from the backend, one per DynamoDB
/// Streams change (see ws_broadcast Lambda). Deliberately loose/dynamic
/// rather than decoded into the app's rich local models (Recommendation,
/// CrowdAlert, etc.) — the server schema is simpler than those structs
/// (no RiskLevel enum, no ActionType, etc.), so this is treated as a
/// notification that something changed server-side, not a drop-in
/// replacement for local simulation state.
struct RealtimePush: Identifiable {
    enum Resource: String {
        case venueState = "venue_state"
        case alert
        case incident
        case recommendation
        case unknown
    }

    let id = UUID()
    let resource: Resource
    let raw: [String: Any]
    let receivedAt: Date = Date()
}

enum WebSocketConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    /// Holds a human-readable reason, e.g. "token expired" or a network error.
    case failed(String)
}

/// Maintains a live WebSocket connection to the CrowdShield backend
/// (Phase 4) and republishes incoming pushes. Reconnects automatically with
/// backoff if the connection drops — matches the brief's "network outages"
/// constraint by degrading to silence (no live updates) rather than
/// crashing or blocking the rest of the app, which keeps working off local
/// simulation state regardless of connection status.
@MainActor
final class CrowdShieldRealtimeClient: NSObject, ObservableObject {
    @Published private(set) var connectionState: WebSocketConnectionState = .disconnected
    @Published private(set) var lastPush: RealtimePush?

    /// Callback invoked for every push, in addition to `lastPush` — lets
    /// CrowdSimulationService react (e.g. show a banner) without needing to
    /// observe this object directly as an environment object too.
    var onPush: ((RealtimePush) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var reconnectAttempt = 0
    private var reconnectWorkItem: DispatchWorkItem?
    private var isStopping = false

    /// The token/venue this client is currently using — kept so reconnect
    /// attempts (e.g. after a network blip) can retry with the same
    /// credentials without the caller needing to re-supply them.
    private var currentToken: String?
    private var currentVenueId: String?

    func connect(idToken: String, venueId: String = CrowdShieldConfig.defaultVenueId) {
        isStopping = false
        currentToken = idToken
        currentVenueId = venueId
        reconnectAttempt = 0
        openSocket()
    }

    func disconnect() {
        isStopping = true
        reconnectWorkItem?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        connectionState = .disconnected
    }

    // MARK: - Private

    private func openSocket() {
        guard let token = currentToken, let venueId = currentVenueId else { return }

        var components = URLComponents(url: CrowdShieldConfig.webSocketURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "venueId", value: venueId),
        ]
        guard let url = components.url else { return }

        connectionState = .connecting

        let config = URLSessionConfiguration.default
        let urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        session = urlSession

        let socketTask = urlSession.webSocketTask(with: url)
        task = socketTask
        socketTask.resume()

        listen()
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .failure(let error):
                    self.handleFailure(error)
                case .success(let message):
                    self.handleMessage(message)
                    // Keep listening for the next message on this same task.
                    self.listen()
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case .data(let d):
            data = d
        case .string(let s):
            data = s.data(using: .utf8)
        @unknown default:
            data = nil
        }

        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resourceRaw = json["resource"] as? String,
              let item = json["item"] as? [String: Any]
        else {
            return
        }

        let resource = RealtimePush.Resource(rawValue: resourceRaw) ?? .unknown
        let push = RealtimePush(resource: resource, raw: item)
        lastPush = push
        onPush?(push)
    }

    private func handleFailure(_ error: Error) {
        guard !isStopping else { return }
        connectionState = .failed(error.localizedDescription)
        scheduleReconnect()
    }

    /// Exponential backoff capped at 30s, so a prolonged outage (matching
    /// the brief's network-outage constraint) doesn't hammer the API —
    /// the app's local simulation keeps working regardless while this
    /// quietly keeps trying to restore live updates in the background.
    private func scheduleReconnect() {
        reconnectWorkItem?.cancel()
        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(reconnectAttempt)), 30.0)

        let workItem = DispatchWorkItem { [weak self] in
            self?.openSocket()
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}

extension CrowdShieldRealtimeClient: URLSessionWebSocketDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor in
            self.connectionState = .connected
            self.reconnectAttempt = 0
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor in
            guard !self.isStopping else { return }
            self.connectionState = .failed("Connection closed (code \(closeCode.rawValue)).")
            self.scheduleReconnect()
        }
    }
}
