import Foundation
import CoreLocation

enum APIError: LocalizedError {
    case notAuthenticated
    case forbidden
    case server(status: Int, message: String)
    case network(underlying: Error)
    case decoding

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Sign in required."
        case .forbidden:
            return "Your account doesn't have permission for this action."
        case .server(let status, let message):
            return "Server error (\(status)): \(message)"
        case .network(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .decoding:
            return "Received an unexpected response from the server."
        }
    }
}

/// Talks to the CrowdShield HTTP API deployed in Phase 1/2
/// (Cognito-JWT-protected Lambda + DynamoDB backend). Every call requires a
/// bearer token; `CrowdSimulationService`/`OfflineSyncManager` are
/// responsible for not calling this when signed out, and for queuing writes
/// locally if a call fails (see OfflineSyncManager's offline-first design).
final class CrowdShieldAPIClient {
    static let shared = CrowdShieldAPIClient()

    private let session = URLSession.shared

    // MARK: - Venue state

    @discardableResult
    func putVenueState(
        venueId: String = CrowdShieldConfig.defaultVenueId,
        density: Double?,
        movementSpeed: Double?,
        hotspots: [String],
        zones: [[String: Any]]? = nil,
        idToken: String
    ) async throws -> [String: Any] {
        var body: [String: Any] = ["hotspots": hotspots]
        if let density { body["density"] = density }
        if let movementSpeed { body["movementSpeed"] = movementSpeed }
        if let zones { body["zones"] = zones }

        return try await request(
            path: "/venues/\(venueId)/state",
            method: "PUT",
            body: body,
            idToken: idToken
        )
    }

    // MARK: - Alerts

    @discardableResult
    func postAlert(
        venueId: String = CrowdShieldConfig.defaultVenueId,
        severity: String,
        type: String,
        message: String,
        idToken: String
    ) async throws -> [String: Any] {
        try await request(
            path: "/venues/\(venueId)/alerts",
            method: "POST",
            body: ["severity": severity, "type": type, "message": message],
            idToken: idToken
        )
    }

    // MARK: - Incidents

    @discardableResult
    func postIncident(
        venueId: String = CrowdShieldConfig.defaultVenueId,
        report: IncidentReport,
        idToken: String
    ) async throws -> [String: Any] {
        var body: [String: Any] = [
            "description": report.description,
            "category": report.type,
            "status": report.status,
            "reportedBy": report.reporterName,
        ]
        if let coordinate = report.coordinate {
            body["location"] = [
                "lat": coordinate.latitude,
                "lon": coordinate.longitude,
            ]
        }

        return try await request(
            path: "/venues/\(venueId)/incidents",
            method: "POST",
            body: body,
            idToken: idToken
        )
    }

    // MARK: - Recommendations

    @discardableResult
    func postRecommendationAck(
        venueId: String = CrowdShieldConfig.defaultVenueId,
        action: String,
        reason: String?,
        priority: String,
        idToken: String
    ) async throws -> [String: Any] {
        var body: [String: Any] = ["action": action, "status": "acknowledged", "priority": priority]
        if let reason { body["reason"] = reason }

        return try await request(
            path: "/venues/\(venueId)/recommendations",
            method: "POST",
            body: body,
            idToken: idToken
        )
    }

    // MARK: - AI incident summary (Stage 1, Bedrock-backed)

    /// Requests a fresh server-generated summary for the given venue. The
    /// Lambda pulls venue-state (including per-zone detail synced by
    /// syncVenueStateToBackendIfDue) and recent alerts directly from
    /// DynamoDB rather than trusting client-submitted numbers — this call
    /// sends no body, just identifies which venue to summarize.
    func postGeneratedSummary(
        venueId: String = CrowdShieldConfig.defaultVenueId,
        idToken: String
    ) async throws -> IncidentSummary {
        let json = try await request(
            path: "/venues/\(venueId)/summary",
            method: "POST",
            body: [:],
            idToken: idToken
        )
        guard let headline = json["headline"] as? String,
              let body = json["body"] as? String,
              let nextStep = json["recommendedNextStep"] as? String
        else {
            throw APIError.server(status: 502, message: "Malformed summary response.")
        }
        return IncidentSummary(generatedAt: Date(), headline: headline, body: body, recommendedNextStep: nextStep)
    }

    // MARK: - Venues registry

    /// Lists all venues. Any authenticated user (Public or Command) can
    /// call this — it's how the venue picker populates its list.
    func getVenues(idToken: String) async throws -> [Venue] {
        let json = try await request(path: "/venues", method: "GET", body: nil, idToken: idToken)
        guard let venuesRaw = json["venues"] as? [[String: Any]] else {
            return []
        }
        let data = try JSONSerialization.data(withJSONObject: venuesRaw)
        return try JSONDecoder().decode([Venue].self, from: data)
    }

    /// Creates a new venue. Command-group only server-side — a Public
    /// caller gets APIError.forbidden (403) from `require_command()` in
    /// the Lambda, surfaced here like any other API error.
    @discardableResult
    func createVenue(name: String, description: String?, idToken: String) async throws -> Venue {
        var body: [String: Any] = ["name": name]
        if let description, !description.isEmpty { body["description"] = description }

        let json = try await request(path: "/venues", method: "POST", body: body, idToken: idToken)
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(Venue.self, from: data)
    }

    // MARK: - Private

    private func request(
        path: String,
        method: String,
        body: [String: Any]?,
        idToken: String
    ) async throws -> [String: Any] {
        guard !idToken.isEmpty else { throw APIError.notAuthenticated }

        let url = CrowdShieldConfig.apiBaseURL.appendingPathComponent(path)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw APIError.network(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.decoding
        }

        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

        switch httpResponse.statusCode {
        case 200..<300:
            return json
        case 401:
            throw APIError.notAuthenticated
        case 403:
            throw APIError.forbidden
        default:
            let message = json["error"] as? String ?? "Unknown error."
            throw APIError.server(status: httpResponse.statusCode, message: message)
        }
    }
}
