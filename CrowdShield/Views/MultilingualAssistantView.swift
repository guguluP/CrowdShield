import SwiftUI
#if canImport(AVFoundation)
import AVFoundation
#endif

/// A command-room tool for broadcasting pre-vetted safety announcements in the
/// public's preferred language, plus a lightweight voice-readout of the current
/// venue status — the "multilingual AI assistant" and "voice-enabled command
/// center" bonus features from the brief, implemented as a real, usable surface
/// rather than a mockup.
struct MultilingualAssistantView: View {
    @EnvironmentObject var crowdService: CrowdSimulationService
    @State private var selectedLanguage: SupportedLanguage = .english
    @State private var lastBroadcast: (key: AnnouncementLibrary.AnnouncementKey, text: String)?
    @State private var isSpeaking = false

    #if canImport(AVFoundation)
    private let synthesizer = AVSpeechSynthesizer()
    #endif

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "waveform.and.mic")
                            .font(.system(size: 30))
                            .foregroundStyle(.cyan)
                        Text("Multilingual Command Assistant")
                            .font(.title3.weight(.bold))
                            .tracking(-0.3)
                        Text("Broadcast vetted safety announcements in the crowd's language, or have the current situation read aloud.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section("Broadcast Language") {
                    Picker("Language", selection: $selectedLanguage) {
                        ForEach(SupportedLanguage.allCases) { lang in
                            Text(lang.rawValue).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Quick Announcements") {
                    ForEach(AnnouncementLibrary.AnnouncementKey.allCases, id: \.self) { key in
                        Button {
                            broadcast(key)
                        } label: {
                            HStack {
                                Image(systemName: "megaphone.fill")
                                    .foregroundStyle(.cyan)
                                Text(key.rawValue)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                }

                if let lastBroadcast {
                    Section("Last Broadcast (\(selectedLanguage.rawValue))") {
                        Text(lastBroadcast.text)
                            .font(.body)
                            .padding(.vertical, 4)
                    }
                }

                Section("Situation Voice Briefing") {
                    Button {
                        speakSituationBriefing()
                    } label: {
                        HStack {
                            Image(systemName: isSpeaking ? "waveform" : "play.circle.fill")
                                .foregroundStyle(.cyan)
                            Text(isSpeaking ? "Speaking…" : "Read Current Status Aloud")
                        }
                    }
                    .disabled(isSpeaking)

                    Text("Reads overall risk, top concern zone, and active flow anomalies using on-device speech synthesis — works fully offline.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("AI Assistant")
        }
    }

    private func broadcast(_ key: AnnouncementLibrary.AnnouncementKey) {
        let text = AnnouncementLibrary.text(for: key, language: selectedLanguage)
        lastBroadcast = (key, text)
        HapticManager.trigger(.medium)
        speak(text, languageCode: selectedLanguage.localeCode)
    }

    private func speakSituationBriefing() {
        let risk = crowdService.overallRisk
        let topZone = crowdService.zones.sorted { $0.riskScore > $1.riskScore }.first
        var parts: [String] = ["Current venue risk level is \(risk.rawValue)."]
        parts.append("Overall stampede likelihood is \(Int(crowdService.overallStampedeLikelihood * 100)) percent.")
        if let topZone {
            parts.append("Highest concern zone is \(topZone.name), at \(Int(topZone.riskScore * 100)) percent risk, stampede likelihood \(Int(topZone.stampedeLikelihood * 100)) percent.")
        }
        if !crowdService.panicPropagationFronts.isEmpty {
            parts.append("Panic is actively spreading from \(crowdService.panicPropagationFronts.prefix(2).joined(separator: " and ")).")
        }
        if !crowdService.flowIssues.isEmpty {
            parts.append("\(crowdService.flowIssues.count) active flow anomaly or anomalies detected.")
        } else {
            parts.append("No flow anomalies detected.")
        }
        speak(parts.joined(separator: " "), languageCode: "en")
    }

    private func speak(_ text: String, languageCode: String) {
        #if canImport(AVFoundation)
        isSpeaking = true
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode) ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
        // Rough completion estimate since AVSpeechSynthesizerDelegate would need
        // a class-based wrapper; good enough to gate the button for this prototype.
        let estimatedDuration = max(1.5, Double(text.count) * 0.06)
        DispatchQueue.main.asyncAfter(deadline: .now() + estimatedDuration) {
            isSpeaking = false
        }
        #else
        isSpeaking = false
        #endif
    }
}

#Preview {
    MultilingualAssistantView()
        .environmentObject(CrowdSimulationService())
}
