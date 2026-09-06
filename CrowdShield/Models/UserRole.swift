import Foundation
import SwiftUI
import Combine

// MARK: - User Roles

/// The two access levels supported by CrowdShield.
enum UserRole: String, Codable, CaseIterable, Identifiable {
    case commandControl = "Command & Control"
    case publicUser = "Public User"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .commandControl: return "Command"
        case .publicUser: return "Public"
        }
    }

    var systemImage: String {
        switch self {
        case .commandControl: return "shield.checkered"
        case .publicUser: return "person.fill"
        }
    }

    var summary: String {
        switch self {
        case .commandControl:
            return "For event safety officers, control room staff, and first responders. Access to live analytics, the command dashboard, and operational tools."
        case .publicUser:
            return "For attendees and the general public. Live safety map, alerts, incident reporting, and guidance — no operational or sensitive data."
        }
    }

    /// Whether this role is allowed to view sensitive, aggregate operational data
    /// (e.g. full density analytics, evacuation routing controls, sensor ingestion).
    var hasOperationalAccess: Bool {
        self == .commandControl
    }
}

/// Session object tracking who is currently signed in, backed by real
/// Cognito authentication (Phase 3). Role is derived from Cognito group
/// membership — a user only gets `.commandControl` if their token actually
/// contains the "Command" group, so this is now a real security boundary at
/// the API layer, not just a UI gate.
@MainActor
final class UserSession: ObservableObject {
    @Published var role: UserRole? = nil
    @Published var displayName: String = ""
    @Published var accessCodeError: String? = nil
    @Published var isAuthenticating: Bool = false

    /// True from app launch until the initial restoreSession() attempt
    /// completes (whether it succeeds or not). Lets the UI show a brief
    /// loading state instead of flashing the sign-in screen for the split
    /// second before a stored session is silently restored.
    @Published var isRestoringSession: Bool = true

    /// Set when sign-in returns NEW_PASSWORD_REQUIRED, so the UI can present
    /// a "choose a new password" step before completing sign-in.
    @Published var pendingPasswordChallenge: (email: String, session: String)? = nil

    /// Set after a successful signUp call, so the UI can present a
    /// "check your email for a code" confirmation step. Holds the password
    /// too so we can sign the user straight in once confirmed, rather than
    /// making them type their credentials twice.
    @Published var pendingConfirmation: (email: String, password: String)? = nil

    /// Set after a successful forgotPassword call, so the UI can present a
    /// "enter the code from your email + a new password" step. A plain
    /// String? rather than a labeled tuple — Swift collapses single-element
    /// labeled tuples like (email: String) to just String at compile time,
    /// which silently breaks `.email` access at every call site.
    @Published var pendingPasswordReset: String? = nil

    /// The venue this session is currently operating on (Phase 6). Nil
    /// means no venue has been selected yet — the app should show the venue
    /// picker rather than any venue-specific screen. Persisted via
    /// UserDefaults (not Keychain — venue choice isn't sensitive) so the
    /// last-used venue is remembered across launches, though it's always
    /// re-validated against the live registry by VenueSelectionView rather
    /// than trusted blindly (a venue could have been renamed/removed since
    /// last launch).
    @Published var selectedVenue: Venue? {
        didSet {
            if let venue = selectedVenue,
               let data = try? JSONEncoder().encode(venue) {
                UserDefaults.standard.set(data, forKey: Self.selectedVenueDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.selectedVenueDefaultsKey)
            }
        }
    }

    private static let selectedVenueDefaultsKey = "com.crowdshield.selectedVenue"

    /// Reads back a previously-persisted venue selection, if any. Called
    /// from init so a returning user doesn't see the picker every launch —
    /// but the picker/dashboard should still confirm this venue still
    /// exists via getVenues() rather than assuming it's still valid.
    static func loadPersistedVenue() -> Venue? {
        guard let data = UserDefaults.standard.data(forKey: selectedVenueDefaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(Venue.self, from: data)
    }

    init() {
        selectedVenue = Self.loadPersistedVenue()
    }

    /// idToken/refreshToken live in memory for the current session.
    /// refreshToken (and the email it belongs to) is additionally persisted
    /// to the Keychain on sign-in and read back by restoreSession() at next
    /// launch — see KeychainStore. idToken itself is never persisted since
    /// it's short-lived (1h) and would be stale by the next launch anyway.
    private(set) var idToken: String = ""
    private(set) var refreshToken: String = ""
    private var email: String = ""

    var isSignedIn: Bool { role != nil }

    /// Attempts a silent sign-in using a refresh token persisted in the
    /// Keychain from a previous launch. Call once at app start (see
    /// CrowdShieldApp) before the sign-in screen would otherwise show —
    /// on success the user skips straight to their previous role without
    /// re-entering credentials; on failure (no stored token, or the refresh
    /// token itself has expired/been revoked) this is a silent no-op and
    /// the normal sign-in flow shows as usual.
    func restoreSession() async {
        defer { isRestoringSession = false }

        guard let storedRefreshToken = KeychainStore.get(.refreshToken),
              let storedEmail = KeychainStore.get(.email),
              !storedRefreshToken.isEmpty
        else {
            return
        }

        do {
            let session = try await CrowdShieldAuthService.shared.refresh(
                refreshToken: storedRefreshToken,
                email: storedEmail
            )
            apply(session)
        } catch {
            // Stored token is stale/invalid — clear it so we don't keep
            // retrying a doomed refresh on every future launch, and fall
            // through to the normal sign-in screen.
            KeychainStore.clearAll()
        }
    }

    /// Signs in with a real Cognito email/password. On success, role is
    /// derived from the token's group membership: users in the "Command"
    /// Cognito group get `.commandControl`, everyone else gets `.publicUser`.
    /// If Cognito requires a new password, this populates
    /// `pendingPasswordChallenge` instead of throwing, so the UI can show a
    /// dedicated step — it is not an error state.
    func signIn(email: String, password: String) async {
        isAuthenticating = true
        accessCodeError = nil
        defer { isAuthenticating = false }

        do {
            let session = try await CrowdShieldAuthService.shared.signIn(email: email, password: password)
            apply(session)
        } catch AuthError.newPasswordRequired(let session) {
            pendingPasswordChallenge = (email: email, session: session)
        } catch {
            accessCodeError = error.localizedDescription
        }
    }

    /// Registers a new account, then moves to the "check your email"
    /// confirmation step (`pendingConfirmation`) rather than signing in
    /// immediately — Cognito requires the emailed code to be confirmed
    /// before the account can authenticate.
    func signUp(email: String, password: String) async {
        isAuthenticating = true
        accessCodeError = nil
        defer { isAuthenticating = false }

        do {
            try await CrowdShieldAuthService.shared.signUp(email: email, password: password)
            pendingConfirmation = (email: email, password: password)
        } catch {
            accessCodeError = error.localizedDescription
        }
    }

    /// Confirms the emailed code, then immediately signs in with the
    /// password captured at signUp time so the user doesn't have to type
    /// their credentials a second time. By the time this sign-in call
    /// happens, the backend's PostConfirmation trigger has already run, so
    /// the returned token carries the Public group.
    func confirmSignUp(code: String) async {
        guard let pending = pendingConfirmation else { return }
        isAuthenticating = true
        accessCodeError = nil
        defer { isAuthenticating = false }

        do {
            try await CrowdShieldAuthService.shared.confirmSignUp(email: pending.email, code: code)
            let session = try await CrowdShieldAuthService.shared.signIn(email: pending.email, password: pending.password)
            pendingConfirmation = nil
            apply(session)
        } catch {
            accessCodeError = error.localizedDescription
        }
    }

    func resendConfirmationCode() async {
        guard let pending = pendingConfirmation else { return }
        do {
            try await CrowdShieldAuthService.shared.resendConfirmationCode(email: pending.email)
        } catch {
            accessCodeError = error.localizedDescription
        }
    }

    func cancelPendingConfirmation() {
        pendingConfirmation = nil
        accessCodeError = nil
    }

    /// Starts a password reset. Always moves to the pendingPasswordReset
    /// step regardless of whether the email actually has an account —
    /// Cognito's ForgotPassword API deliberately doesn't reveal that
    /// distinction (see CrowdShieldAuthService.forgotPassword), so the app
    /// shouldn't try to infer or reveal it either. The UI's copy at this
    /// step should read "if an account exists, a code was sent" rather than
    /// confirming existence.
    func forgotPassword(email: String) async {
        isAuthenticating = true
        accessCodeError = nil
        defer { isAuthenticating = false }

        do {
            try await CrowdShieldAuthService.shared.forgotPassword(email: email)
            pendingPasswordReset = email
        } catch {
            // A genuine network/client error (not "user not found", which
            // Cognito hides) still surfaces normally — only existence is
            // deliberately withheld, not real failures.
            accessCodeError = error.localizedDescription
        }
    }

    /// Completes a password reset using the emailed code, then signs the
    /// user straight in with their new password so they land in the app
    /// rather than back at a blank sign-in form.
    func confirmPasswordReset(code: String, newPassword: String) async {
        guard let pendingEmail = pendingPasswordReset else { return }
        isAuthenticating = true
        accessCodeError = nil
        defer { isAuthenticating = false }

        do {
            try await CrowdShieldAuthService.shared.confirmForgotPassword(
                email: pendingEmail,
                code: code,
                newPassword: newPassword
            )
            let session = try await CrowdShieldAuthService.shared.signIn(email: pendingEmail, password: newPassword)
            pendingPasswordReset = nil
            apply(session)
        } catch {
            accessCodeError = error.localizedDescription
        }
    }

    func cancelPendingPasswordReset() {
        pendingPasswordReset = nil
        accessCodeError = nil
    }
    func completeNewPassword(_ newPassword: String) async {
        guard let challenge = pendingPasswordChallenge else { return }
        isAuthenticating = true
        accessCodeError = nil
        defer { isAuthenticating = false }

        do {
            let session = try await CrowdShieldAuthService.shared.completeNewPassword(
                email: challenge.email,
                newPassword: newPassword,
                session: challenge.session
            )
            pendingPasswordChallenge = nil
            apply(session)
        } catch {
            accessCodeError = error.localizedDescription
        }
    }

    /// Refreshes the ID token using the stored refresh token. Called by
    /// CrowdSimulationService before making an API call if the current
    /// token may have expired (1 hour validity per the Cognito app client).
    func refreshTokenIfNeeded() async {
        guard !refreshToken.isEmpty else { return }
        do {
            let session = try await CrowdShieldAuthService.shared.refresh(refreshToken: refreshToken, email: email)
            apply(session)
        } catch {
            // Refresh failing silently signs the user out rather than
            // surfacing an error mid-session; they'll be prompted to sign
            // in again next time they try an action that needs a token.
            signOut()
        }
    }

    func signOut() {
        role = nil
        displayName = ""
        accessCodeError = nil
        pendingPasswordChallenge = nil
        pendingConfirmation = nil
        pendingPasswordReset = nil
        idToken = ""
        refreshToken = ""
        email = ""
        selectedVenue = nil
        KeychainStore.clearAll()
    }

    private func apply(_ session: AuthSession) {
        idToken = session.idToken
        refreshToken = session.refreshToken
        email = session.email
        displayName = session.email
        role = session.isCommand ? .commandControl : .publicUser

        // Persist for silent restore on next launch. Only the refresh
        // token and email are stored — never the password, and the
        // short-lived ID/access tokens aren't worth persisting since
        // they'd be expired by the time they're read back anyway.
        if !session.refreshToken.isEmpty {
            KeychainStore.set(session.refreshToken, for: .refreshToken)
            KeychainStore.set(session.email, for: .email)
        }
    }
}
