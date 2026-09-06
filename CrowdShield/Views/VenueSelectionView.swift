import SwiftUI

/// Shown after sign-in, before the main app, when `session.selectedVenue`
/// is nil. Fetches the venue registry (Phase 6) and lets the user pick one.
/// Command users additionally get a "Create venue" form — Public users
/// never see it, since venue creation is Command-only server-side
/// (require_command() in the venues Lambda) and there's no point showing UI
/// for an action that would just come back as a 403.
struct VenueSelectionView: View {
    @EnvironmentObject var session: UserSession
    @EnvironmentObject var crowdService: CrowdSimulationService

    @State private var venues: [Venue] = []
    @State private var isLoading = true
    @State private var loadError: String?

    @State private var isCreatingVenue = false
    @State private var newVenueName = ""
    @State private var newVenueDescription = ""
    @State private var isSubmittingVenue = false
    @State private var createError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    identityStrip

                    header

                    if isLoading {
                        ProgressView("Loading venues…")
                            .padding(.top, 40)
                    } else if let loadError {
                        errorState(loadError)
                    } else if venues.isEmpty && !isCreatingVenue {
                        emptyState
                    } else {
                        venueList
                    }

                    if session.role == .commandControl {
                        if isCreatingVenue {
                            createVenueForm
                                .padding(.horizontal)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        } else {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    isCreatingVenue = true
                                }
                            } label: {
                                Label("Create New Venue", systemImage: "plus.circle.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.bordered)
                            .tint(CrowdShieldTheme.accent(for: session.role))
                            .padding(.horizontal)
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(.top, 24)
            }
            .crowdShieldScreenBackground(accent: CrowdShieldTheme.accent(for: session.role))
#if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
#endif
        }
        .preferredColorScheme(.dark)
        .task {
            await loadVenues()
        }
    }

    /// Always-visible so this screen is never a dead end: shows who's
    /// signed in and as what role (the exact thing that's otherwise
    /// invisible once the navigation bar is hidden), plus a way out via
    /// sign-out if the wrong account/role got restored from a stored
    /// session.
    private var identityStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: session.role?.systemImage ?? "person.fill")
                .foregroundStyle(CrowdShieldTheme.accent(for: session.role))
            VStack(alignment: .leading, spacing: 1) {
                Text(session.displayName.isEmpty ? "Signed in" : session.displayName)
                    .font(.caption.weight(.medium))
                Text(session.role?.rawValue ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                session.signOut()
            } label: {
                Label("Sign Out", systemImage: "arrow.backward.circle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .adaptiveGlassCard(cornerRadius: 18)
        .padding(.horizontal)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(CrowdShieldTheme.accent(for: session.role))
                .symbolRenderingMode(.hierarchical)
            Text("Select a Venue")
                .font(.largeTitle.weight(.bold))
                .tracking(-0.6)
            Text(
                session.role == .commandControl
                    ? "Choose a venue to manage, or create a new one."
                    : "Choose the event you're attending."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
        }
    }

    private var venueList: some View {
        VStack(spacing: 12) {
            ForEach(venues) { venue in
                Button {
                    select(venue)
                } label: {
                    VenueRow(venue: venue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "building.2")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("No venues yet")
                .font(.headline)
            Text(
                session.role == .commandControl
                    ? "Create the first venue below to get started."
                    : "No events are set up yet. Check back soon."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.top, 20)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Retry") {
                Task { await loadVenues() }
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 20)
    }

    @ViewBuilder
    private var createVenueForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New venue")
                .font(.headline)

            TextField("Venue name", text: $newVenueName)
                .crowdShieldField()

            TextField("Description (optional)", text: $newVenueDescription)
                .crowdShieldField()

            if let createError {
                Label(createError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    withAnimation { isCreatingVenue = false }
                    newVenueName = ""
                    newVenueDescription = ""
                    createError = nil
                }

                Spacer()

                Button {
                    Task { await createVenue() }
                } label: {
                    if isSubmittingVenue {
                        ProgressView()
                    } else {
                        Text("Create & Continue")
                            .font(.headline)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(CrowdShieldTheme.commandAccent)
                .disabled(newVenueName.trimmingCharacters(in: .whitespaces).isEmpty || isSubmittingVenue)
            }
        }
        .padding(18)
        .adaptiveGlassCard(cornerRadius: 22, tint: CrowdShieldTheme.commandAccent)
    }

    // MARK: - Actions

    private func loadVenues() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        guard !session.idToken.isEmpty else {
            loadError = "You must be signed in to view venues."
            return
        }

        do {
            venues = try await CrowdShieldAPIClient.shared.getVenues(idToken: session.idToken)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func createVenue() async {
        isSubmittingVenue = true
        createError = nil
        defer { isSubmittingVenue = false }

        do {
            let venue = try await CrowdShieldAPIClient.shared.createVenue(
                name: newVenueName.trimmingCharacters(in: .whitespaces),
                description: newVenueDescription.trimmingCharacters(in: .whitespaces),
                idToken: session.idToken
            )
            select(venue)
        } catch {
            createError = error.localizedDescription
        }
    }

    private func select(_ venue: Venue) {
        session.selectedVenue = venue
    }
}

private struct VenueRow: View {
    let venue: Venue

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(CrowdShieldTheme.publicAccent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(CrowdShieldTheme.publicAccent.opacity(0.16)))

            VStack(alignment: .leading, spacing: 2) {
                Text(venue.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let description = venue.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .adaptiveGlassCard(cornerRadius: 18)
    }
}
