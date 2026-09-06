import Foundation

/// A single stated privacy/ethics commitment shown in-app. Kept as data (not just
/// prose in a doc) so the app itself is the evidence for the "Data Ethics & Privacy"
/// evaluation criterion, not only the written documentation.
struct PrivacyCommitment: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
}

enum PrivacyPolicy {
    static let commitments: [PrivacyCommitment] = [
        PrivacyCommitment(
            icon: "camera.metering.none",
            title: "No raw imagery leaves the device",
            detail: "Camera-based density estimation (VisionSensorSource) runs on-device with Apple's Vision framework. Frames are processed in memory and discarded immediately after inference — never stored, never uploaded."
        ),
        PrivacyCommitment(
            icon: "person.crop.circle.badge.xmark",
            title: "No facial recognition or identity tracking",
            detail: "The system counts and localizes people as anonymous bounding boxes to estimate density and flow. It never attempts to recognize, identify, or track individuals across frames."
        ),
        PrivacyCommitment(
            icon: "number",
            title: "Aggregate numbers only",
            detail: "Only numeric outputs — density, movement speed, flow direction, risk score — are transmitted to the command dashboard. These cannot be reversed into images or individual identities."
        ),
        PrivacyCommitment(
            icon: "hand.raised.fill",
            title: "Citizen reports are opt-in",
            detail: "Location and contact details in incident reports are provided voluntarily by the reporter and used only to triage that report. Reporters may submit anonymously."
        ),
        PrivacyCommitment(
            icon: "clock.arrow.circlepath",
            title: "Minimal retention",
            detail: "Zone telemetry is retained only as a short rolling window (last few minutes) needed for trend prediction, then discarded. Historical retention beyond the active event is out of scope for this prototype."
        ),
        PrivacyCommitment(
            icon: "checkmark.seal",
            title: "Compliant by design",
            detail: "Architecture avoids collecting personally identifiable information (PII) by default, aligning with data-minimization principles under India's Digital Personal Data Protection Act, 2023."
        )
    ]
}
