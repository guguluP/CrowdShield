import Foundation

/// A generated natural-language brief of the current venue situation, meant for
/// a command-room officer to read aloud or forward to senior authorities without
/// having to manually synthesize numbers from the dashboard themselves.
struct IncidentSummary: Identifiable {
    let id = UUID()
    let generatedAt: Date
    let headline: String
    let body: String
    let recommendedNextStep: String
}

/// Abstraction over "something that can turn structured venue state into a
/// readable summary." Kept as a protocol so the app can run fully offline
/// with TemplateSummaryProvider or on-device FoundationModelsSummaryProvider
/// as a fallback — the production path (CrowdSimulationService.
/// generateSummary()) tries a Bedrock-backed server summary first via
/// CrowdShieldAPIClient.postGeneratedSummary(), which is what actually calls
/// a hosted model; no API key lives in this client, only the backend's own
/// endpoint URL and the caller's Cognito token do.
protocol IncidentSummaryProvider {
    func summarize(
        overallRisk: RiskLevel,
        zones: [CrowdZone],
        flowIssues: [FlowIssue],
        recentAlerts: [CrowdAlert]
    ) async -> IncidentSummary
}

/// Default, fully offline provider: deterministic natural-language generation
/// from a template, so the feature works in the demo (and in real venues with
/// no network) without depending on a live LLM call.
final class TemplateSummaryProvider: IncidentSummaryProvider {
    func summarize(
        overallRisk: RiskLevel,
        zones: [CrowdZone],
        flowIssues: [FlowIssue],
        recentAlerts: [CrowdAlert]
    ) async -> IncidentSummary {
        let riskyZones = zones.filter { $0.riskLevel == .high || $0.riskLevel == .critical }
            .sorted { $0.riskScore > $1.riskScore }

        let headline: String
        switch overallRisk {
        case .critical: headline = "Critical risk across \(riskyZones.count) zone(s) — immediate action required"
        case .high: headline = "Elevated risk detected in \(riskyZones.count) zone(s)"
        case .moderate: headline = "Moderate crowd pressure building"
        case .safe: headline = "Venue operating within safe parameters"
        }

        var bodyLines: [String] = []
        if let worst = riskyZones.first {
            bodyLines.append(
                "\(worst.name) is the primary concern, at \(String(format: "%.1f", worst.density)) people/m² " +
                "with a risk score of \(String(format: "%.0f", worst.riskScore * 100))%."
            )
        }
        if !flowIssues.isEmpty {
            let kinds = Set(flowIssues.map(\.kind.rawValue)).joined(separator: ", ")
            bodyLines.append("Flow analysis has flagged: \(kinds).")
        }
        let highStampede = zones.filter { $0.stampedeLikelihood >= 0.5 }.sorted { $0.stampedeLikelihood > $1.stampedeLikelihood }
        if let top = highStampede.first {
            bodyLines.append(
                "Stampede likelihood peaks at \(top.name) (\(Int(top.stampedeLikelihood * 100))%)."
            )
        }
        let highPanic = zones.filter { $0.panicIntensity >= 0.4 }.sorted { $0.panicIntensity > $1.panicIntensity }
        if let top = highPanic.first {
            bodyLines.append(
                "Panic intensity is elevated at \(top.name) (\(Int(top.panicIntensity * 100))%) and may spread to adjacent zones."
            )
        }
        if let latestAlert = recentAlerts.first {
            bodyLines.append("Most recent alert: \"\(latestAlert.title)\" at \(latestAlert.timestamp.formatted(date: .omitted, time: .shortened)).")
        }
        if bodyLines.isEmpty {
            bodyLines.append("No significant anomalies in the last update cycle.")
        }

        let nextStep: String
        switch overallRisk {
        case .critical: nextStep = "Deploy additional personnel to the highest-risk zone and trigger evacuation guidance now."
        case .high: nextStep = "Pre-position staff near the flagged zone(s) and monitor closely for the next 2-3 minutes."
        case .moderate: nextStep = "Continue monitoring; no intervention required yet."
        case .safe: nextStep = "No action needed."
        }

        return IncidentSummary(
            generatedAt: Date(),
            headline: headline,
            body: bodyLines.joined(separator: " "),
            recommendedNextStep: nextStep
        )
    }
}

// Note: what used to be a RemoteLLMSummaryProvider stub here has been
// superseded by a real implementation — see CrowdShieldAPIClient.
// postGeneratedSummary() (calls the Bedrock-backed /venues/{id}/summary
// Lambda) and CrowdSimulationService.generateSummary() (tries that first,
// falls back to the providers below on any failure). Keeping the fallback
// logic in the service rather than a third IncidentSummaryProvider
// implementation avoids two parallel places that both claim to own
// "what happens when the remote call fails."

// MARK: - Multilingual Assistant

enum SupportedLanguage: String, CaseIterable, Identifiable {
    case english = "English"
    case hindi = "हिंदी"
    case bengali = "বাংলা"
    case tamil = "தமிழ்"
    case telugu = "తెలుగు"
    case marathi = "मराठी"

    var id: String { rawValue }
    var localeCode: String {
        switch self {
        case .english: return "en"
        case .hindi: return "hi"
        case .bengali: return "bn"
        case .tamil: return "ta"
        case .telugu: return "te"
        case .marathi: return "mr"
        }
    }
}

/// Pre-authored, safety-critical announcement templates in each supported
/// language. Using vetted templates (rather than live machine translation)
/// for anything broadcast to the public during an emergency avoids the risk
/// of a translation error causing panic — machine translation is reserved
/// for the AI assistant's free-form Q&A, not for safety broadcasts.
enum AnnouncementLibrary {
    static func text(for key: AnnouncementKey, language: SupportedLanguage) -> String {
        templates[key]?[language] ?? templates[key]?[.english] ?? ""
    }

    enum AnnouncementKey: String, CaseIterable {
        case stayCalm = "Stay Calm"
        case moveToExit = "Move to Nearest Exit"
        case avoidZone = "Avoid Congested Zone"
        case followStaff = "Follow Staff Instructions"
    }

    private static let templates: [AnnouncementKey: [SupportedLanguage: String]] = [
        .stayCalm: [
            .english: "Please remain calm. There is no immediate danger. Follow staff instructions.",
            .hindi: "कृपया शांत रहें। कोई तत्काल खतरा नहीं है। कर्मचारियों के निर्देशों का पालन करें।",
            .bengali: "অনুগ্রহ করে শান্ত থাকুন। কোনো তাৎক্ষণিক বিপদ নেই। কর্মীদের নির্দেশ অনুসরণ করুন।",
            .tamil: "தயவுசெய்து அமைதியாக இருங்கள். உடனடி ஆபத்து இல்லை. பணியாளர்களின் வழிமுறைகளைப் பின்பற்றவும்.",
            .telugu: "దయచేసి ప్రశాంతంగా ఉండండి. తక్షణ ప్రమాదం లేదు. సిబ్బంది సూచనలను అనుసరించండి.",
            .marathi: "कृपया शांत रहा. कोणताही तात्काळ धोका नाही. कर्मचाऱ्यांच्या सूचनांचे पालन करा."
        ],
        .moveToExit: [
            .english: "For your safety, please move calmly toward the nearest marked exit.",
            .hindi: "अपनी सुरक्षा के लिए, कृपया निकटतम चिह्नित निकास की ओर शांति से बढ़ें।",
            .bengali: "আপনার নিরাপত্তার জন্য, নিকটতম চিহ্নিত প্রস্থানের দিকে শান্তভাবে এগিয়ে যান।",
            .tamil: "உங்கள் பாதுகாப்பிற்காக, அருகிலுள்ள குறியிடப்பட்ட வெளியேறும் வழியை நோக்கி அமைதியாக நகரவும்.",
            .telugu: "మీ భద్రత కోసం, దయచేసి సమీపంలోని గుర్తించబడిన నిష్క్రమణ వైపు ప్రశాంతంగా వెళ్లండి.",
            .marathi: "तुमच्या सुरक्षिततेसाठी, कृपया जवळच्या चिन्हांकित बाहेर पडण्याच्या दिशेने शांतपणे जा."
        ],
        .avoidZone: [
            .english: "Please avoid the Central Plaza area at this time due to high congestion.",
            .hindi: "अत्यधिक भीड़ के कारण कृपया इस समय सेंट्रल प्लाजा क्षेत्र से बचें।",
            .bengali: "অত্যধিক ভিড়ের কারণে অনুগ্রহ করে এই মুহূর্তে সেন্ট্রাল প্লাজা এলাকা এড়িয়ে চলুন।",
            .tamil: "அதிக நெரிசல் காரணமாக இந்த நேரத்தில் சென்ட்ரல் பிளாசா பகுதியைத் தவிர்க்கவும்.",
            .telugu: "అధిక రద్దీ కారణంగా దయచేసి ఈ సమయంలో సెంట్రల్ ప్లాజా ప్రాంతాన్ని నివారించండి.",
            .marathi: "जास्त गर्दीमुळे कृपया यावेळी सेंट्रल प्लाझा परिसर टाळा."
        ],
        .followStaff: [
            .english: "Trained safety staff are nearby. Please follow their guidance.",
            .hindi: "प्रशिक्षित सुरक्षा कर्मचारी आस-पास हैं। कृपया उनके मार्गदर्शन का पालन करें।",
            .bengali: "প্রশিক্ষিত নিরাপত্তা কর্মীরা কাছাকাছি আছেন। অনুগ্রহ করে তাদের নির্দেশনা অনুসরণ করুন।",
            .tamil: "பயிற்சி பெற்ற பாதுகாப்பு பணியாளர்கள் அருகில் உள்ளனர். அவர்களின் வழிகாட்டுதலைப் பின்பற்றவும்.",
            .telugu: "శిక్షణ పొందిన భద్రతా సిబ్బంది సమీపంలో ఉన్నారు. దయచేసి వారి మార్గదర్శకత్వాన్ని అనుసరించండి.",
            .marathi: "प्रशिक्षित सुरक्षा कर्मचारी जवळ आहेत. कृपया त्यांच्या मार्गदर्शनाचे पालन करा."
        ]
    ]
}
