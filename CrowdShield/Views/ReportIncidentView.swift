import SwiftUI
import CoreLocation

struct ReportIncidentView: View {
    @EnvironmentObject var crowdService: CrowdSimulationService
    @EnvironmentObject var locationManager: LocationManager

    @State private var incidentType = "Overcrowding"
    @State private var severity = "Medium"
    @State private var description = ""
    @State private var reporterName = ""
    @State private var showConfirmation = false
    @State private var isSubmitting = false
    @State private var showRecent = false
    @State private var formError: String?

    private let incidentTypes = [
        "Overcrowding",
        "Blocked Exit",
        "Panic / Fighting",
        "Injured Person",
        "Suspicious Activity",
        "Other"
    ]

    private let severities = ["Low", "Medium", "High", "Critical"]

    private var canSubmit: Bool {
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                introSection
                connectivitySection
                typeSection
                severitySection
                descriptionSection
                detailsSection
                locationSection
                submitSection

                if !crowdService.incidents.isEmpty {
                    recentReportsSection
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle("Report Incident")
            .disabled(isSubmitting)
            .overlay {
                if isSubmitting {
                    submittingOverlay
                }
            }
            .alert("Report Submitted", isPresented: $showConfirmation) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Thank you. Authorities have been notified and will verify the situation. Stay calm and follow official guidance.")
            }
            .alert("Cannot Submit", isPresented: Binding(
                get: { formError != nil },
                set: { if !$0 { formError = nil } }
            )) {
                Button("OK", role: .cancel) { formError = nil }
            } message: {
                Text(formError ?? "")
            }
        }
    }

    // MARK: - Sections

    private var introSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.title2)
                    .foregroundStyle(CrowdShieldTheme.publicAccent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Citizen safety report")
                        .font(.subheadline.weight(.semibold))
                    Text("Describe what you see. Your location helps command verify and respond faster.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var connectivitySection: some View {
        Group {
            if crowdService.reachability.status == .offline {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "wifi.slash")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("You're offline")
                                .font(.caption.weight(.semibold))
                            Text("Your report will be saved and sent automatically once connection is restored.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if crowdService.offlineSync.hasPending {
                            Text("\(crowdService.offlineSync.pendingQueue.count) queued")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.orange.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else if crowdService.offlineSync.isSyncing {
                Section {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Syncing queued reports…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var typeSection: some View {
        Section("Incident Type") {
            Picker("Type", selection: $incidentType) {
                ForEach(incidentTypes, id: \.self) { type in
                    Label(type, systemImage: icon(for: type)).tag(type)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: incidentType) { _, _ in
                HapticManager.trigger(.selection)
            }
        }
    }

    private var severitySection: some View {
        Section("Severity") {
            Picker("Severity", selection: $severity) {
                ForEach(severities, id: \.self) { level in
                    Text(level).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: severity) { _, newValue in
                if newValue == "Critical" || newValue == "High" {
                    HapticManager.trigger(.warning)
                } else {
                    HapticManager.trigger(.selection)
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(severityColor)
                    .frame(width: 10, height: 10)
                Text(severityHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var descriptionSection: some View {
        Section("Description") {
            TextField("Describe what you are seeing…", text: $description, axis: .vertical)
                .lineLimit(3...8)

            HStack {
                Spacer()
                Text("\(description.count)/500")
                    .font(.caption2)
                    .foregroundStyle(description.count > 500 ? .red : .secondary)
            }
        }
    }

    private var detailsSection: some View {
        Section("Your Details (Optional)") {
            TextField("Name or phone", text: $reporterName)
                .textContentType(.name)
            Text("Reports can be anonymous. Providing a contact helps if authorities need clarification.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var locationSection: some View {
        Section("Location") {
            if let loc = locationManager.userLocation {
                Label("Using current location", systemImage: "location.fill")
                    .foregroundStyle(.green)
                Text(String(format: "%.5f, %.5f", loc.latitude, loc.longitude))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Label("Location unavailable — will use venue center", systemImage: "location.slash")
                    .foregroundStyle(.orange)
                if let err = locationManager.locationError {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button {
                    locationManager.requestLocation()
                    HapticManager.trigger(.light)
                } label: {
                    Label("Request Location Access", systemImage: "location.circle")
                }
            }
        }
    }

    private var submitSection: some View {
        Section {
            Button {
                submitReport()
            } label: {
                HStack {
                    Spacer()
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                        Text("Sending…")
                            .fontWeight(.semibold)
                    } else {
                        Label("Submit Report", systemImage: "paperplane.fill")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .listRowBackground(canSubmit ? CrowdShieldTheme.publicAccent : Color.gray.opacity(0.45))
            .foregroundStyle(.white)
            .disabled(!canSubmit)
        } footer: {
            Text("False reports waste emergency resources. Submit only genuine safety concerns.")
                .font(.caption2)
        }
    }

    private var recentReportsSection: some View {
        Section {
            DisclosureGroup("Your recent reports (\(crowdService.incidents.count))", isExpanded: $showRecent) {
                ForEach(crowdService.incidents.prefix(5)) { report in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(report.type)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(report.status)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(CrowdShieldTheme.publicAccent.opacity(0.2))
                                .clipShape(Capsule())
                        }
                        Text(report.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Text(report.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var submittingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(CrowdShieldTheme.publicAccent)
                Text("Sending report to command…")
                    .font(.subheadline.weight(.medium))
            }
            .padding(28)
            .adaptiveGlassCard(cornerRadius: 16)
        }
    }

    // MARK: - Helpers

    private var severityColor: Color {
        switch severity {
        case "Critical": return .red
        case "High": return .orange
        case "Low": return .green
        default: return .yellow
        }
    }

    private var severityHint: String {
        switch severity {
        case "Critical": return "Immediate danger — crush, stampede, or life threat"
        case "High": return "Rapidly worsening congestion or blocked exits"
        case "Low": return "Minor concern; still useful for awareness"
        default: return "Noticeable issue that may escalate"
        }
    }

    private func icon(for type: String) -> String {
        switch type {
        case "Overcrowding": return "person.3.fill"
        case "Blocked Exit": return "door.left.hand.closed"
        case "Panic / Fighting": return "bolt.heart.fill"
        case "Injured Person": return "cross.case.fill"
        case "Suspicious Activity": return "eye.fill"
        default: return "ellipsis.circle.fill"
        }
    }

    private func submitReport() {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            formError = "Please add a short description of what you observed."
            HapticManager.trigger(.error)
            return
        }
        guard trimmed.count <= 500 else {
            formError = "Please keep the description under 500 characters."
            HapticManager.trigger(.error)
            return
        }

        isSubmitting = true
        HapticManager.trigger(.medium)

        // Simulate network latency for real-time feel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            let report = IncidentReport(
                type: incidentType,
                description: trimmed,
                coordinate: locationManager.userLocation ?? VenueInfo.center,
                timestamp: Date(),
                reporterName: reporterName.trimmingCharacters(in: .whitespaces).isEmpty
                    ? "Anonymous"
                    : reporterName,
                severity: severity,
                status: "Submitted"
            )
            crowdService.offlineSync.submit(report)

            description = ""
            reporterName = ""
            severity = "Medium"
            isSubmitting = false
            showConfirmation = true
            HapticManager.trigger(.success)
        }
    }
}

#Preview {
    ReportIncidentView()
        .environmentObject(CrowdSimulationService())
        .environmentObject(LocationManager())
}
