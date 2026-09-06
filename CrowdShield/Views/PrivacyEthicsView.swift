import SwiftUI

struct PrivacyEthicsView: View {
    @EnvironmentObject var crowdService: CrowdSimulationService

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(CrowdShieldTheme.publicAccent)
                            .symbolRenderingMode(.hierarchical)
                        Text("Privacy by Design")
                            .font(.title2.weight(.bold))
                            .tracking(-0.4)
                        Text("CrowdShield is built to keep public spaces safer without compromising individual privacy. Here's exactly how.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section("Our Commitments") {
                    ForEach(PrivacyPolicy.commitments) { commitment in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: commitment.icon)
                                .font(.title3)
                                .foregroundStyle(CrowdShieldTheme.publicAccent)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(commitment.title)
                                    .font(.subheadline.bold())
                                Text(commitment.detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Active Sensing Sources") {
                    HStack {
                        Image(systemName: "sensor.fill")
                            .foregroundStyle(CrowdShieldTheme.publicAccent)
                        Text(crowdService.activeSensorDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    NavigationLink {
                        DataFlowDiagramView()
                    } label: {
                        Label("View Data Flow Diagram", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                }
            }
            .navigationTitle("Privacy & Ethics")
        }
    }
}

/// A simple in-app illustration of where data originates, what's processed
/// on-device vs transmitted, and what's discarded — useful both for judges
/// and for real deployment sign-off conversations with venue authorities.
struct DataFlowDiagramView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                flowStep(
                    icon: "camera.fill",
                    title: "1. Camera Frame Captured",
                    detail: "Held only in device memory.",
                    color: .blue
                )
                flowArrow
                flowStep(
                    icon: "cpu",
                    title: "2. On-Device Vision Inference",
                    detail: "Person count + bounding boxes computed locally. Frame discarded immediately.",
                    color: .purple
                )
                flowArrow
                flowStep(
                    icon: "number.circle.fill",
                    title: "3. Numeric Reading Only",
                    detail: "Density, speed, flow direction — no imagery.",
                    color: .orange
                )
                flowArrow
                flowStep(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "4. Transmitted to Command Dashboard",
                    detail: "Encrypted in transit. Aggregated per zone.",
                    color: .green
                )
                flowArrow
                flowStep(
                    icon: "trash",
                    title: "5. Rolling Deletion",
                    detail: "Retained only for the short trend window, then discarded.",
                    color: .red
                )
            }
            .padding()
        }
        .navigationTitle("Data Flow")
    }

    private func flowStep(icon: String, title: String, detail: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .adaptiveGlassCard(cornerRadius: 12)
    }

    private var flowArrow: some View {
        Image(systemName: "arrow.down")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
    }
}
