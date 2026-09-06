import SwiftUI

struct RoleSelectionView: View {
    @EnvironmentObject var session: UserSession

    @State private var selectedRole: UserRole? = nil
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var newPassword: String = ""
    @State private var confirmationCode: String = ""
    @State private var resetCode: String = ""
    @State private var resetNewPassword: String = ""
    /// Only meaningful for .publicUser — Command accounts are always
    /// provisioned manually (see backend PostConfirmation trigger, which
    /// never assigns the Command group), so there's no self-signup path for
    /// that role and no toggle is shown for it.
    @State private var isSigningUp: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header

                    if let challenge = session.pendingPasswordChallenge {
                        newPasswordForm(email: challenge.email)
                            .padding(.horizontal)
                    } else if let pending = session.pendingConfirmation {
                        confirmationForm(email: pending.email)
                            .padding(.horizontal)
                    } else if let pendingResetEmail = session.pendingPasswordReset {
                        passwordResetForm(email: pendingResetEmail)
                            .padding(.horizontal)
                    } else {
                        VStack(spacing: 14) {
                            ForEach(UserRole.allCases) { role in
                                RoleCard(
                                    role: role,
                                    isSelected: selectedRole == role,
                                    action: {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                            selectedRole = role
                                            session.accessCodeError = nil
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)

                        if let selectedRole {
                            signInForm(for: selectedRole)
                                .padding(.horizontal)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(.top, 36)
            }
            .crowdShieldScreenBackground(
                accent: selectedRole == .commandControl
                    ? CrowdShieldTheme.commandAccent
                    : CrowdShieldTheme.publicAccent
            )
#if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
#endif
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(CrowdShieldTheme.publicAccent.opacity(0.16))
                    .frame(width: 88, height: 88)
                Image(systemName: "shield.checkered")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(CrowdShieldTheme.publicAccent)
                    .symbolRenderingMode(.hierarchical)
            }
            VStack(spacing: 6) {
                Text("CrowdShield")
                    .font(.largeTitle.weight(.bold))
                    .tracking(-0.8)
                Text("Live crowd safety, designed for the people who keep venues calm.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func signInForm(for role: UserRole) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(formTitle(for: role))
                .font(.title3.weight(.semibold))

            if role == .publicUser {
                Picker("Mode", selection: $isSigningUp) {
                    Text("Sign In").tag(false)
                    Text("Create Account").tag(true)
                }
                .pickerStyle(.segmented)
            }

            TextField("Email", text: $email)
                .textContentType(.username)
                .autocorrectionDisabled()
#if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
#endif
                .crowdShieldField()

            SecureField("Password", text: $password)
                .textContentType(isSigningUp ? .newPassword : .password)
                .crowdShieldField()

            if role == .publicUser && isSigningUp {
                Text("At least 8 characters, with uppercase, lowercase, and a number.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !(role == .publicUser && isSigningUp) {
                Button("Forgot password?") {
                    Task { await session.forgotPassword(email: email) }
                }
                .font(.caption)
                .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || session.isAuthenticating)
            }

            if let error = session.accessCodeError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    if role == .publicUser && isSigningUp {
                        await session.signUp(email: email, password: password)
                    } else {
                        await session.signIn(email: email, password: password)
                    }
                }
            } label: {
                if session.isAuthenticating {
                    ProgressView().tint(.white)
                } else {
                    Text(role == .publicUser && isSigningUp ? "Create Account" : "Continue")
                }
            }
            .buttonStyle(CrowdShieldPrimaryButtonStyle(
                tint: CrowdShieldTheme.accent(for: role),
                isEnabled: !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !session.isAuthenticating
            ))
            .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty || session.isAuthenticating)
        }
        .padding(18)
        .adaptiveGlassCard(cornerRadius: 22, tint: CrowdShieldTheme.accent(for: role))
    }

    private func formTitle(for role: UserRole) -> String {
        if role == .commandControl { return "Command & Control sign-in" }
        return isSigningUp ? "Create your account" : "Sign in"
    }

    @ViewBuilder
    private func confirmationForm(email: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Check your email")
                .font(.title3.weight(.semibold))
            Text("We sent a confirmation code to \(email). Enter it below to finish creating your account.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Confirmation code", text: $confirmationCode)
#if os(iOS)
                .keyboardType(.numberPad)
#endif
                .crowdShieldField()

            if let error = session.accessCodeError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await session.confirmSignUp(code: confirmationCode) }
            } label: {
                if session.isAuthenticating {
                    ProgressView().tint(.white)
                } else {
                    Text("Confirm & Continue")
                }
            }
            .buttonStyle(CrowdShieldPrimaryButtonStyle(
                tint: CrowdShieldTheme.publicAccent,
                isEnabled: !confirmationCode.trimmingCharacters(in: .whitespaces).isEmpty && !session.isAuthenticating
            ))
            .disabled(confirmationCode.trimmingCharacters(in: .whitespaces).isEmpty || session.isAuthenticating)

            HStack {
                Button("Resend code") {
                    Task { await session.resendConfirmationCode() }
                }
                .font(.caption)

                Spacer()

                Button("Cancel", role: .cancel) {
                    session.cancelPendingConfirmation()
                    confirmationCode = ""
                }
                .font(.caption)
            }
        }
        .padding(18)
        .adaptiveGlassCard(cornerRadius: 22, tint: CrowdShieldTheme.publicAccent)
    }

    @ViewBuilder
    private func newPasswordForm(email: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set a new password")
                .font(.title3.weight(.semibold))
            Text("Your account (\(email)) needs a permanent password before you can continue.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField("New password", text: $newPassword)
                .crowdShieldField()

            if let error = session.accessCodeError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await session.completeNewPassword(newPassword) }
            } label: {
                if session.isAuthenticating {
                    ProgressView().tint(.white)
                } else {
                    Text("Set Password & Continue")
                }
            }
            .buttonStyle(CrowdShieldPrimaryButtonStyle(
                tint: CrowdShieldTheme.publicAccent,
                isEnabled: newPassword.count >= 8 && !session.isAuthenticating
            ))
            .disabled(newPassword.count < 8 || session.isAuthenticating)
        }
        .padding(18)
        .adaptiveGlassCard(cornerRadius: 22)
    }

    @ViewBuilder
    private func passwordResetForm(email: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reset your password")
                .font(.title3.weight(.semibold))
            Text("If an account exists for \(email), we've sent a reset code to that address. Enter it below along with your new password.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Reset code", text: $resetCode)
#if os(iOS)
                .keyboardType(.numberPad)
#endif
                .crowdShieldField()

            SecureField("New password", text: $resetNewPassword)
                .crowdShieldField()

            Text("At least 8 characters, with uppercase, lowercase, and a number.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let error = session.accessCodeError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await session.confirmPasswordReset(code: resetCode, newPassword: resetNewPassword) }
            } label: {
                if session.isAuthenticating {
                    ProgressView().tint(.white)
                } else {
                    Text("Reset Password & Sign In")
                }
            }
            .buttonStyle(CrowdShieldPrimaryButtonStyle(
                tint: CrowdShieldTheme.publicAccent,
                isEnabled: !resetCode.trimmingCharacters(in: .whitespaces).isEmpty
                    && resetNewPassword.count >= 8
                    && !session.isAuthenticating
            ))
            .disabled(
                resetCode.trimmingCharacters(in: .whitespaces).isEmpty
                    || resetNewPassword.count < 8
                    || session.isAuthenticating
            )

            HStack {
                Button("Resend code") {
                    Task { await session.forgotPassword(email: email) }
                }
                .font(.caption)

                Spacer()

                Button("Cancel", role: .cancel) {
                    session.cancelPendingPasswordReset()
                    resetCode = ""
                    resetNewPassword = ""
                }
                .font(.caption)
            }
        }
        .padding(18)
        .adaptiveGlassCard(cornerRadius: 22)
    }
}

private struct RoleCard: View {
    let role: UserRole
    let isSelected: Bool
    let action: () -> Void

    private var accent: Color { CrowdShieldTheme.accent(for: role) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: role.systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(accent.opacity(0.16)))

                VStack(alignment: .leading, spacing: 4) {
                    Text(role.rawValue)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(role.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? accent : .secondary.opacity(0.45))
                    .symbolEffect(.bounce, value: isSelected)
            }
            .padding(16)
            .adaptiveGlassCard(cornerRadius: 20, tint: isSelected ? accent : nil)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isSelected ? accent.opacity(0.7) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RoleSelectionView()
        .environmentObject(UserSession())
}
