import SwiftUI

/// Command & Control's account panel: identity, current venue (with a
/// switch action), and sign-out. Extracted from what used to be
/// AccountSettingsView's Command branch so it can be a first-class
/// CommandDestination in the new sidebar/tab navigation (see
/// CommandRootView) rather than living inline in ContentView.
struct CommandAccountView: View {
    @EnvironmentObject var session: UserSession

    var body: some View {
        NavigationStack {
            List {
                Section("Signed in as") {
                    HStack(spacing: 14) {
                        Image(systemName: session.role?.systemImage ?? "person.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(CrowdShieldTheme.commandAccent)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(CrowdShieldTheme.commandAccent.opacity(0.18)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.displayName.isEmpty ? "Operator" : session.displayName)
                                .font(.headline)
                            Text(session.role?.rawValue ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                if let venue = session.selectedVenue {
                    Section("Venue") {
                        HStack {
                            Image(systemName: "building.2.fill")
                                .foregroundStyle(CrowdShieldTheme.publicAccent)
                            Text(venue.name)
                        }
                        Button {
                            session.selectedVenue = nil
                        } label: {
                            Label("Switch Venue", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        session.signOut()
                    } label: {
                        Label("Sign Out / Switch Role", systemImage: "arrow.backward.circle")
                    }
                }
            }
            .navigationTitle("Account")
        }
    }
}
