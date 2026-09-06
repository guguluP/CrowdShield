import Foundation
import CoreLocation
import SwiftUI
import Combine

// MARK: - Core Models

struct CrowdZone: Identifiable, Equatable {
    let id: UUID
    var name: String
    var coordinate: CLLocationCoordinate2D
    var density: Double          // people per m² (0.0 – 8.0+)
    var movementSpeed: Double    // m/s
    var flowDirection: Double    // degrees
    var isBottleneck: Bool
    var riskScore: Double        // 0.0 – 1.0
    /// Explicit stampede / crush likelihood (0.0 – 1.0) from RiskPredictionEngine.
    var stampedeLikelihood: Double
    /// Panic intensity (0.0 – 1.0); seeds locally and propagates via venue graph.
    var panicIntensity: Double
    var lastUpdated: Date

    init(
        id: UUID = UUID(),
        name: String,
        coordinate: CLLocationCoordinate2D,
        density: Double,
        movementSpeed: Double,
        flowDirection: Double,
        isBottleneck: Bool,
        riskScore: Double,
        stampedeLikelihood: Double = 0,
        panicIntensity: Double = 0,
        lastUpdated: Date
    ) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.density = density
        self.movementSpeed = movementSpeed
        self.flowDirection = flowDirection
        self.isBottleneck = isBottleneck
        self.riskScore = riskScore
        self.stampedeLikelihood = stampedeLikelihood
        self.panicIntensity = panicIntensity
        self.lastUpdated = lastUpdated
    }

    static func == (lhs: CrowdZone, rhs: CrowdZone) -> Bool {
        lhs.id == rhs.id
            && lhs.density == rhs.density
            && lhs.riskScore == rhs.riskScore
            && lhs.isBottleneck == rhs.isBottleneck
            && lhs.movementSpeed == rhs.movementSpeed
            && lhs.stampedeLikelihood == rhs.stampedeLikelihood
            && lhs.panicIntensity == rhs.panicIntensity
    }

    var riskLevel: RiskLevel {
        switch riskScore {
        case 0.0..<0.35: return .safe
        case 0.35..<0.6: return .moderate
        case 0.6..<0.8: return .high
        default: return .critical
        }
    }

    var densityColor: Color {
        switch density {
        case 0..<2: return .green
        case 2..<4: return .yellow
        case 4..<6: return .orange
        default: return .red
        }
    }

    /// Map circle radius in meters derived from density.
    var heatRadius: CLLocationDistance {
        35 + density * 14
    }
}

enum RiskLevel: String, CaseIterable {
    case safe = "Safe"
    case moderate = "Moderate"
    case high = "High"
    case critical = "Critical"

    var color: Color {
        switch self {
        case .safe: return .green
        case .moderate: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }

    var icon: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .moderate: return "exclamationmark.triangle"
        case .high: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }

    var sortOrder: Int {
        switch self {
        case .safe: return 0
        case .moderate: return 1
        case .high: return 2
        case .critical: return 3
        }
    }
}

struct CrowdAlert: Identifiable {
    let id: UUID
    let title: String
    let message: String
    let severity: RiskLevel
    let timestamp: Date
    let coordinate: CLLocationCoordinate2D?
    let recommendedAction: String

    init(
        id: UUID = UUID(),
        title: String,
        message: String,
        severity: RiskLevel,
        timestamp: Date,
        coordinate: CLLocationCoordinate2D?,
        recommendedAction: String
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.severity = severity
        self.timestamp = timestamp
        self.coordinate = coordinate
        self.recommendedAction = recommendedAction
    }
}

struct Recommendation: Identifiable, Equatable {
    let id: UUID
    let title: String
    let detail: String
    let priority: Int          // 1 = highest
    let icon: String
    let actionType: ActionType
    var isAcknowledged: Bool
    var acknowledgedAt: Date?
    var acknowledgedBy: String?

    init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        priority: Int,
        icon: String,
        actionType: ActionType,
        isAcknowledged: Bool = false,
        acknowledgedAt: Date? = nil,
        acknowledgedBy: String? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.priority = priority
        self.icon = icon
        self.actionType = actionType
        self.isAcknowledged = isAcknowledged
        self.acknowledgedAt = acknowledgedAt
        self.acknowledgedBy = acknowledgedBy
    }

    enum ActionType: String {
        case openExit = "Open Exit"
        case closeGate = "Close Gate"
        case redeploy = "Redeploy Staff"
        case announce = "Public Announcement"
        case redirect = "Redirect Flow"
        case barricade = "Change Barricade"
    }

    static func == (lhs: Recommendation, rhs: Recommendation) -> Bool {
        lhs.id == rhs.id && lhs.isAcknowledged == rhs.isAcknowledged
    }
}

struct IncidentReport: Identifiable {
    let id: UUID
    var type: String
    var description: String
    var coordinate: CLLocationCoordinate2D?
    var timestamp: Date
    var reporterName: String
    var severity: String
    var status: String

    init(
        id: UUID = UUID(),
        type: String,
        description: String,
        coordinate: CLLocationCoordinate2D?,
        timestamp: Date,
        reporterName: String,
        severity: String = "Medium",
        status: String = "Submitted"
    ) {
        self.id = id
        self.type = type
        self.description = description
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.reporterName = reporterName
        self.severity = severity
        self.status = status
    }
}

struct VenueInfo {
    static let name = "TechNova Festival Grounds"
    static let center = CLLocationCoordinate2D(latitude: 28.6139, longitude: 77.2090) // Delhi example
    static let span = 0.012
}

/// A venue from the backend registry (Phase 6) — distinct from the static
/// VenueInfo above, which predates multi-venue support and is kept for any
/// map-center/span defaults not yet threaded through venue selection.
struct Venue: Identifiable, Equatable, Codable {
    var id: String { venueId }
    let venueId: String
    let name: String
    let description: String?
    let createdAt: String?
    let createdBy: String?
}
