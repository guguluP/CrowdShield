import SwiftUI

struct ContentView: View {
    @EnvironmentObject var crowdService: CrowdSimulationService
    @EnvironmentObject var session: UserSession

    var body: some View {
        CrowdShieldPlatformReader { _ in
            Group {
                if session.isRestoringSession {
                    restoringView
                } else if let role = session.role {
                    if session.selectedVenue != nil {
                        RoleTabView(role: role)
                    } else {
                        VenueSelectionView()
                    }
                } else {
                    RoleSelectionView()
                }
            }
            .onAppear {
                // Start live simulation once initial load finishes (or immediately if already ready)
                if !crowdService.isLoading {
                    crowdService.startSimulation()
                }
            }
            .onChange(of: crowdService.isLoading) { _, loading in
                if !loading {
                    crowdService.startSimulation()
                }
            }
        }
    }

    private var restoringView: some View {
        VStack(spacing: 18) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(CrowdShieldTheme.publicAccent)
                .symbolEffect(.pulse, options: .repeating)
            ProgressView()
                .controlSize(.large)
                .tint(CrowdShieldTheme.publicAccent)
            Text("Restoring session")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .crowdShieldScreenBackground()
    }
}

/// Routes to a role-specific root view. Public and Command diverge enough
/// in navigation shape (see PublicTabView / CommandRootView) that a single
/// shared TabView branching internally was making the overlap worse, not
/// better — this makes the split explicit at the type level.
private struct RoleTabView: View {
    let role: UserRole

    var body: some View {
        if role == .commandControl {
            CommandRootView()
        } else {
            PublicTabView()
        }
    }
}

/// Public User navigation: citizen-facing safety tools only. Deliberately
/// does NOT include Recommendations/Actions — that view acknowledges
/// operational recommendations against the Command-only backend endpoint
/// (require_command() server-side) and was never actually usable by a
/// Public account; showing it was a leftover from before roles had real
/// backend enforcement, not a deliberate feature for citizens.
private struct PublicTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MapHeatView()
                .tabItem { Label("Map", systemImage: "map.fill") }
                .tag(0)

            AlertsView()
                .tabItem { Label("Alerts", systemImage: "bell.badge.fill") }
                .tag(1)

            ReportIncidentView()
                .tabItem { Label("Report", systemImage: "exclamationmark.bubble.fill") }
                .tag(2)

            MultilingualAssistantView()
                .tabItem { Label("Assist", systemImage: "waveform.and.mic") }
                .tag(3)

            AccountSettingsView()
                .tabItem { Label("Privacy", systemImage: "hand.raised.fill") }
                .tag(4)
        }
        .tint(CrowdShieldTheme.publicAccent)
    }
}

/// Public User's Privacy & Data Ethics screen, with a compact account
/// footer (sign-out, current venue). Command & Control now has its own
/// dedicated CommandAccountView (see CommandRootView) rather than sharing
/// this component — the two roles' account needs diverged enough
/// (Command needs venue-switching prominence; Public needs the privacy
/// explainer front and center) that a shared branching view was adding
/// complexity without saving real code.
private struct AccountSettingsView: View {
    @EnvironmentObject var session: UserSession

    var body: some View {
        PrivacyEthicsView()
            .safeAreaInset(edge: .bottom) {
                accountFooter
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .adaptiveGlassCard(cornerRadius: 20)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
    }

    private var accountFooter: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(CrowdShieldTheme.publicAccent)
                .frame(width: 36, height: 36)
                .background(Circle().fill(CrowdShieldTheme.publicAccent.opacity(0.16)))
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayName.isEmpty ? "Guest" : session.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let venue = session.selectedVenue {
                    Button {
                        session.selectedVenue = nil
                    } label: {
                        Text(venue.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            Button(role: .destructive) {
                session.signOut()
            } label: {
                Text("Sign Out")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(CrowdSimulationService())
        .environmentObject(LocationManager())
        .environmentObject(UserSession())
}
