import SwiftUI

struct RecommendationsView: View {
    @EnvironmentObject var crowdService: CrowdSimulationService
    @State private var filter: RecFilter = .active
    @State private var acknowledgingID: UUID?
    @State private var appear = false

    enum RecFilter: String, CaseIterable {
        case active = "Active"
        case acknowledged = "Acknowledged"
        case all = "All"
    }

    private var filtered: [Recommendation] {
        let sorted = crowdService.recommendations.sorted {
            if $0.isAcknowledged != $1.isAcknowledged { return !$0.isAcknowledged && $1.isAcknowledged }
            return $0.priority < $1.priority
        }
        switch filter {
        case .active: return sorted.filter { !$0.isAcknowledged }
        case .acknowledged: return sorted.filter(\.isAcknowledged)
        case .all: return sorted
        }
    }

    private var activeCount: Int {
        crowdService.recommendations.filter { !$0.isAcknowledged }.count
    }

    private var doneCount: Int {
        crowdService.recommendations.filter(\.isAcknowledged).count
    }

    var body: some View {
        NavigationStack {
            Group {
                if crowdService.isLoading {
                    loadingState
                } else if crowdService.recommendations.isEmpty {
                    emptyState
                } else if filtered.isEmpty {
                    filterEmptyState
                } else {
                    listContent
                }
            }
            .navigationTitle("Recommended Actions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Text("\(doneCount)/\(crowdService.recommendations.count) ack")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .safeAreaInset(edge: .top) {
                if !crowdService.recommendations.isEmpty {
                    filterBar
                }
            }
        }
    }

    // MARK: - Content

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                headerBanner

                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, rec in
                    RecommendationCard(
                        recommendation: rec,
                        isBusy: acknowledgingID == rec.id,
                        onAcknowledge: { acknowledge(rec) },
                        onUndo: { undo(rec) }
                    )
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 12)
                    .animation(
                        .spring(response: 0.45, dampingFraction: 0.82).delay(Double(index) * 0.04),
                        value: appear
                    )
                }
            }
            .padding()
        }
        .crowdShieldScreenBackground(accent: CrowdShieldTheme.commandAccent)
        .onAppear {
            appear = false
            withAnimation { appear = true }
        }
        .onChange(of: filter) { _, _ in
            appear = false
            withAnimation { appear = true }
        }
    }

    private var headerBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lightbulb.max.fill")
                    .foregroundStyle(.yellow)
                Text("AI intervention queue")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if activeCount > 0 {
                    Text("\(activeCount) pending")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
            Text("Prioritized actions from live crowd analytics. Acknowledge once ground teams execute or accept the order.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveGlassCard(cornerRadius: 18, tint: CrowdShieldTheme.commandAccent)
    }

    private var filterBar: some View {
        Picker("Filter", selection: $filter) {
            ForEach(RecFilter.allCases, id: \.self) { f in
                Text(f.rawValue).tag(f)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .onChange(of: filter) { _, _ in
            HapticManager.trigger(.selection)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(CrowdShieldTheme.commandAccent)
            Text("Generating recommendations…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Recommendations Yet",
            systemImage: "lightbulb.slash",
            description: Text("When crowd risk rises, AI-suggested interventions will appear here for authorities to acknowledge.")
        )
    }

    private var filterEmptyState: some View {
        ContentUnavailableView(
            filter == .acknowledged ? "Nothing Acknowledged" : "All Clear",
            systemImage: filter == .acknowledged ? "checkmark.circle" : "tray",
            description: Text(
                filter == .acknowledged
                    ? "Acknowledge an action card to track it here."
                    : "No active recommendations in this filter."
            )
        )
    }

    // MARK: - Actions

    private func acknowledge(_ rec: Recommendation) {
        acknowledgingID = rec.id
        HapticManager.trigger(.medium)
        // Short delay for polish / “dispatch” feel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                crowdService.acknowledgeRecommendation(rec.id)
            }
            acknowledgingID = nil
        }
    }

    private func undo(_ rec: Recommendation) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            crowdService.unacknowledgeRecommendation(rec.id)
        }
    }
}

// MARK: - Card

struct RecommendationCard: View {
    let recommendation: Recommendation
    var isBusy: Bool = false
    let onAcknowledge: () -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(priorityColor.opacity(recommendation.isAcknowledged ? 0.12 : 0.2))
                        .frame(width: 48, height: 48)
                    Image(systemName: recommendation.icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(recommendation.isAcknowledged ? .secondary : priorityColor)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(recommendation.title)
                            .font(.headline)
                            .strikethrough(recommendation.isAcknowledged, color: .secondary)
                            .foregroundStyle(recommendation.isAcknowledged ? .secondary : .primary)
                        Spacer(minLength: 8)
                        priorityChip
                    }

                    Text(recommendation.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Label(recommendation.actionType.rawValue, systemImage: "tag.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.cyan)

                        if recommendation.isAcknowledged, let at = recommendation.acknowledgedAt {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Label(
                                "Ack \(at, style: .time)",
                                systemImage: "checkmark.seal.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.green)
                        }
                    }
                }
            }

            if recommendation.isAcknowledged {
                if let by = recommendation.acknowledgedBy {
                    Text("Acknowledged by \(by)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button(role: .none, action: onUndo) {
                    Label("Undo acknowledge", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            } else {
                Button(action: onAcknowledge) {
                    HStack {
                        if isBusy {
                            ProgressView()
                                .tint(.white)
                            Text("Dispatching…")
                        } else {
                            Image(systemName: "checkmark.shield.fill")
                            Text("Acknowledge & Dispatch")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(priorityColor)
                .disabled(isBusy)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            recommendation.isAcknowledged
                                ? Color.green.opacity(0.35)
                                : priorityColor.opacity(0.45),
                            lineWidth: recommendation.priority == 1 && !recommendation.isAcknowledged ? 2 : 1
                        )
                )
        )
        .opacity(recommendation.isAcknowledged ? 0.78 : 1)
        .accessibilityElement(children: .contain)
    }

    private var priorityChip: some View {
        Text("P\(recommendation.priority)")
            .font(.caption.bold())
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(priorityColor.opacity(0.22))
            .foregroundStyle(priorityColor)
            .clipShape(Capsule())
    }

    private var priorityColor: Color {
        switch recommendation.priority {
        case 1: return .red
        case 2: return .orange
        default: return .yellow
        }
    }
}

#Preview {
    RecommendationsView()
        .environmentObject(CrowdSimulationService())
}
