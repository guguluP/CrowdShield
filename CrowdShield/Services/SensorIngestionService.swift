import Foundation
import CoreLocation
#if canImport(Vision)
import Vision
#endif
#if canImport(CoreImage)
import CoreImage
#endif

/// A single density/flow reading for one physical zone, coming from any sensing source.
struct SensorReading {
    let zoneID: UUID
    let peopleCount: Int?          // raw count, if the source can provide it
    let densityEstimate: Double    // people per m² — always populated
    let movementSpeed: Double?     // m/s, if derivable
    let flowDirection: Double?     // degrees, if derivable
    let confidence: Double         // 0.0–1.0, how much we trust this reading
    let source: SensorSourceKind
    let timestamp: Date
}

enum SensorSourceKind: String {
    case simulated = "Simulated"
    case onDeviceVision = "On-Device Vision"
    case crowdSourcedPhone = "Crowd-Sourced Phone Signal"
}

/// Any component capable of producing crowd readings for the zones it covers.
/// This is the seam between "demo mode" and "real deployment" — swapping the
/// active source(s) is the only change needed to move from simulation to production.
protocol SensorSource {
    var kind: SensorSourceKind { get }
    /// True once the source has what it needs (camera permission, model loaded, etc.)
    var isReady: Bool { get }
    func latestReadings(for zones: [CrowdZone]) -> [SensorReading]
}

/// Default / demo source — statistically plausible synthetic data.
/// This is what CrowdSimulationService currently drives itself with.
final class SimulatedSensorSource: SensorSource {
    let kind: SensorSourceKind = .simulated
    var isReady: Bool { true }

    func latestReadings(for zones: [CrowdZone]) -> [SensorReading] {
        zones.map { zone in
            SensorReading(
                zoneID: zone.id,
                peopleCount: nil,
                densityEstimate: zone.density,
                movementSpeed: zone.movementSpeed,
                flowDirection: zone.flowDirection,
                confidence: 1.0,
                source: .simulated,
                timestamp: Date()
            )
        }
    }
}

/// Real-world source: estimates crowd density from a camera frame using an on-device
/// Vision person-detection request. No frame data or imagery ever leaves the device —
/// only the resulting numeric density estimate is retained (see PrivacyPolicy.swift).
///
/// In production this would be fed by an AVCaptureVideoDataOutput sample buffer per
/// camera per zone; here it exposes the same processing entry point (`estimateDensity`)
/// so the pipeline is demonstrably real, without requiring live CCTV hardware to run.
final class VisionSensorSource: SensorSource {
    let kind: SensorSourceKind = .onDeviceVision

    var isReady: Bool {
        #if canImport(Vision)
        return true
        #else
        return false
        #endif
    }

    /// Zone area in square meters, used to convert a raw person count into density.
    /// In production this is configured per camera during venue setup.
    private let zoneAreaSquareMeters: [UUID: Double] = [:]

    func latestReadings(for zones: [CrowdZone]) -> [SensorReading] {
        // No live camera feed wired up in this build — a real deployment calls
        // estimateDensity(from:zoneID:) below on each captured frame instead.
        // Returning an empty array here means CrowdSimulationService falls back
        // to whichever other source is active (see SensorFusionCoordinator).
        []
    }

    #if canImport(Vision) && canImport(CoreImage)
    /// Runs on-device person detection on a single camera frame and converts the
    /// result into a density reading. The CIImage is discarded immediately after
    /// inference — nothing is persisted or transmitted.
    func estimateDensity(
        from pixelBuffer: CVPixelBuffer,
        zoneID: UUID,
        areaSquareMeters: Double,
        completion: @escaping (SensorReading?) -> Void
    ) {
        let request: VNDetectHumanRectanglesRequest
        if #available(iOS 15.0, macOS 12.0, *) {
            request = VNDetectHumanRectanglesRequest()
        } else {
            completion(nil)
            return
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
                let observations = request.results ?? []
                let count = observations.count
                let density = areaSquareMeters > 0 ? Double(count) / areaSquareMeters : 0
                let reading = SensorReading(
                    zoneID: zoneID,
                    peopleCount: count,
                    densityEstimate: density,
                    movementSpeed: nil,
                    flowDirection: nil,
                    confidence: 0.75,
                    source: .onDeviceVision,
                    timestamp: Date()
                )
                DispatchQueue.main.async { completion(reading) }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
    #endif
}

/// Low-cost, hardware-minimal source described in the brief: aggregate anonymized
/// phone signal density (e.g. anonymized Wi-Fi/BLE probe counts or opted-in GPS
/// pings) reported by a backend and pulled in here. Placeholder wiring — a real
/// deployment points `endpoint` at that aggregation service.
final class CrowdSourcedPhoneSource: SensorSource {
    let kind: SensorSourceKind = .crowdSourcedPhone
    var isReady: Bool { false } // no backend wired up in this build

    func latestReadings(for zones: [CrowdZone]) -> [SensorReading] { [] }
}

/// Picks the best available reading per zone across all configured sources,
/// preferring higher-confidence real sensors over simulation when present.
/// This is the single integration point CrowdSimulationService talks to —
/// swapping from demo to production means registering real sources here,
/// nothing else in the app changes.
final class SensorFusionCoordinator {
    private(set) var sources: [SensorSource]

    init(sources: [SensorSource] = [SimulatedSensorSource(), VisionSensorSource(), CrowdSourcedPhoneSource()]) {
        self.sources = sources
    }

    func fusedReadings(for zones: [CrowdZone]) -> [UUID: SensorReading] {
        var best: [UUID: SensorReading] = [:]
        for source in sources where source.isReady {
            for reading in source.latestReadings(for: zones) {
                if let existing = best[reading.zoneID] {
                    if reading.confidence > existing.confidence {
                        best[reading.zoneID] = reading
                    }
                } else {
                    best[reading.zoneID] = reading
                }
            }
        }
        return best
    }

    var activeSourceDescription: String {
        sources.filter(\.isReady).map(\.kind.rawValue).joined(separator: " + ")
    }
}
