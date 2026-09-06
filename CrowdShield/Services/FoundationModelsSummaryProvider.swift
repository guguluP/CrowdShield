import Foundation
import FoundationModels

/// On-device AI provider using Apple's Foundation Models framework (AFM 3 Core).
/// Runs entirely on-device — no network call, no API key, no data leaving the
/// phone — which matters here because incident summaries can reference live
/// crowd density and location data that shouldn't be sent off-device unless
/// the operator is online and authenticated (see CrowdSimulationService.
/// generateSummary(), which tries the Bedrock-backed server summary first
/// and falls back to this provider on any failure).
///
/// Falls back to TemplateSummaryProvider whenever the on-device model isn't
/// usable (e.g. Apple Intelligence disabled, unsupported device/simulator, or
/// the device is under memory pressure) — a command-room officer should never
/// be left without a summary because of model availability.
@available(iOS 26.0, macOS 26.0, *)
final class FoundationModelsSummaryProvider: IncidentSummaryProvider {
    private let fallback = TemplateSummaryProvider()

    private let instructions = """
    You are a calm, precise crowd-safety command assistant. You are given the \
    current state of a live event venue: overall risk level, per-zone density \
    and risk data, detected flow issues, and recent alerts. Produce a short \
    situational brief for a command-room safety officer who needs to act \
    quickly. Be factual and specific — cite zone names and numbers you were \
    given. Do not invent data you were not given. Keep the tone urgent but \
    professional, never alarmist.
    """

    func summarize(
        overallRisk: RiskLevel,
        zones: [CrowdZone],
        flowIssues: [FlowIssue],
        recentAlerts: [CrowdAlert]
    ) async -> IncidentSummary {
        let model = SystemLanguageModel.default
        guard model.availability == .available else {
            // Model unavailable on this device/session right now — fall back
            // rather than surface an error to the officer.
            return await fallback.summarize(overallRisk: overallRisk, zones: zones, flowIssues: flowIssues, recentAlerts: recentAlerts)
        }

        let session = LanguageModelSession(instructions: instructions)
        let prompt = buildPrompt(overallRisk: overallRisk, zones: zones, flowIssues: flowIssues, recentAlerts: recentAlerts)

        do {
            let response = try await session.respond(
                to: prompt,
                generating: IncidentBrief.self
            )
            let brief = response.content
            return IncidentSummary(
                generatedAt: Date(),
                headline: brief.headline,
                body: brief.body,
                recommendedNextStep: brief.recommendedNextStep
            )
        } catch {
            // Guardrail rejection, context overflow, or any generation failure —
            // degrade gracefully to the deterministic template rather than
            // leaving the dashboard without a summary.
            return await fallback.summarize(overallRisk: overallRisk, zones: zones, flowIssues: flowIssues, recentAlerts: recentAlerts)
        }
    }

    private func buildPrompt(
        overallRisk: RiskLevel,
        zones: [CrowdZone],
        flowIssues: [FlowIssue],
        recentAlerts: [CrowdAlert]
    ) -> String {
        let riskyZones = zones
            .filter { $0.riskLevel == .high || $0.riskLevel == .critical }
            .sorted { $0.riskScore > $1.riskScore }
            .prefix(5)

        var lines: [String] = ["Overall risk: \(overallRisk.rawValue)"]

        if riskyZones.isEmpty {
            lines.append("No zones currently above moderate risk.")
        } else {
            lines.append("Zones of concern:")
            for zone in riskyZones {
                lines.append(
                    "- \(zone.name): density \(String(format: "%.1f", zone.density)) p/m², " +
                    "risk \(String(format: "%.0f", zone.riskScore * 100))%, " +
                    "bottleneck: \(zone.isBottleneck ? "yes" : "no")"
                )
            }
        }

        if !flowIssues.isEmpty {
            lines.append("Flow issues detected:")
            for issue in flowIssues.prefix(5) {
                lines.append("- \(issue.kind.rawValue) at \(issue.zoneName): \(issue.detail)")
            }
        }

                let highStampede = zones.filter { $0.stampedeLikelihood >= 0.45 }
            .sorted { $0.stampedeLikelihood > $1.stampedeLikelihood }
        if !highStampede.isEmpty {
            lines.append("Stampede likelihood:")
            for z in highStampede.prefix(3) {
                lines.append("- \(z.name): \(Int(z.stampedeLikelihood * 100))%")
            }
        }
        let highPanic = zones.filter { $0.panicIntensity >= 0.35 }
            .sorted { $0.panicIntensity > $1.panicIntensity }
        if !highPanic.isEmpty {
            lines.append("Panic intensity (may propagate along walkable paths):")
            for z in highPanic.prefix(3) {
                lines.append("- \(z.name): \(Int(z.panicIntensity * 100))%")
            }
        }

        if let latest = recentAlerts.first {
            lines.append("Most recent alert: \(latest.title) — \(latest.message)")
        }

        return lines.joined(separator: "\n")
    }
}

/// Structured output schema for the on-device model. Using @Generable lets
/// Foundation Models constrain generation to this exact shape instead of
/// free-form text we'd have to parse, which is both more reliable and lets
/// us reuse the same IncidentSummary type the template provider produces.
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct IncidentBrief {
    @Guide(description: "A single-sentence headline summarizing the venue's current safety state.")
    var headline: String

    @Guide(description: "Two to four sentences giving the operator the specific detail behind the headline — cite the zone names and numbers provided.")
    var body: String

    @Guide(description: "One concrete, actionable next step the command-room officer should take right now.")
    var recommendedNextStep: String
}
