import SwiftUI

struct AlertsView: View {
    @EnvironmentObject var crowdService: CrowdSimulationService
    @State private var selectedLanguage = "English"
    @State private var previousAlertCount = 0

    private let languages = ["English", "हिन्दी", "বাংলা", "தமிழ்", "తెలుగు", "मराठी"]

    var body: some View {
        NavigationStack {
            Group {
                if crowdService.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(CrowdShieldTheme.publicAccent)
                        Text("Connecting to alert feed…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if crowdService.alerts.isEmpty {
                    ContentUnavailableView(
                        "No Active Alerts",
                        systemImage: "bell.slash",
                        description: Text("Crowd conditions are currently stable.\nSimulation will generate alerts when risk rises.")
                    )
                } else {
                    List {
                        ForEach(crowdService.alerts) { alert in
                            AlertRow(alert: alert, language: selectedLanguage)
                                .listRowBackground(alert.severity.color.opacity(0.08))
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                        .onDelete { indexSet in
                            crowdService.alerts.remove(atOffsets: indexSet)
                            HapticManager.trigger(.light)
                        }
                    }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    #else
                    .listStyle(.inset)
                    #endif
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: crowdService.alerts.map(\.id))
                }
            }
            .navigationTitle("Live Alerts")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Menu {
                        ForEach(languages, id: \.self) { lang in
                            Button(lang) {
                                selectedLanguage = lang
                                HapticManager.trigger(.selection)
                            }
                        }
                    } label: {
                        Label(selectedLanguage, systemImage: "globe")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Clear All") {
                        withAnimation {
                            crowdService.clearAlerts()
                        }
                        HapticManager.trigger(.medium)
                    }
                    .disabled(crowdService.alerts.isEmpty)
                }
            }
            .onChange(of: crowdService.alerts.count) { oldCount, newCount in
                if newCount > oldCount,
                   let newest = crowdService.alerts.first,
                   newest.severity == .critical || newest.severity == .high {
                    // Service already haptics on generation; reinforce UI pulse feel
                    previousAlertCount = newCount
                }
            }
        }
    }
}

struct AlertRow: View {
    let alert: CrowdAlert
    let language: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: alert.severity.icon)
                    .foregroundStyle(alert.severity.color)
                    .symbolEffect(.bounce, value: alert.id)
                Text(localizedTitle)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(alert.severity.rawValue.uppercased())
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(alert.severity.color.opacity(0.18), in: Capsule())
                    .foregroundStyle(alert.severity.color)
            }

            Text(localizedMessage)
                .font(.subheadline)
                .foregroundStyle(.primary)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                Text(alert.recommendedAction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)

            Text(alert.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }

    private var localizedTitle: String {
        switch language {
        case "हिन्दी": return "उच्च जोखिम क्षेत्र"
        case "বাংলা": return "উচ্চ ঝুঁকিপূর্ণ অঞ্চল"
        case "தமிழ்": return "அதிக ஆபத்து மண்டலம்"
        default: return alert.title
        }
    }

    private var localizedMessage: String {
        switch language {
        case "हिन्दी": return "घनत्व सुरक्षित सीमा से अधिक है। कृपया शांत रहें और निर्देशों का पालन करें।"
        case "বাংলা": return "ঘনত্ব নিরাপদ সীমা ছাড়িয়ে গেছে। অনুগ্রহ করে শান্ত থাকুন।"
        default: return alert.message
        }
    }
}

#Preview {
    AlertsView()
        .environmentObject(CrowdSimulationService())
}
