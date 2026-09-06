import Foundation

/// Errors surfaced by CrowdShieldAuthService, kept small and UI-friendly
/// rather than exposing raw Cognito exception names.
enum AuthError: LocalizedError {
    case invalidCredentials
    case newPasswordRequired(session: String)
    case network(underlying: Error)
    case unexpectedResponse(String)
    case usernameExists
    case invalidConfirmationCode
    case weakPassword(String)
    case userNotFound

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Incorrect email or password."
        case .newPasswordRequired:
            return "You must set a new password before continuing."
        case .network(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .unexpectedResponse(let message):
            return message
        case .usernameExists:
            return "An account with this email already exists. Try signing in instead."
        case .invalidConfirmationCode:
            return "That code isn't correct or has expired. Check your email and try again."
        case .weakPassword(let detail):
            return detail
        case .userNotFound:
            return "No account found with that email."
        }
    }
}

/// The decoded, app-relevant contents of a successful sign-in.
struct AuthSession {
    let idToken: String
    let accessToken: String
    let refreshToken: String
    /// Cognito group names pulled from the ID token's `cognito:groups` claim.
    let groups: [String]
    let email: String

    var isCommand: Bool { groups.contains("Command") }
}

/// Thin wrapper around Amazon Cognito's plain-HTTPS identity-provider API
/// (InitiateAuth / RespondToAuthChallenge). No AWS SDK dependency — the same
/// two calls used to validate the backend by hand during Phase 2 testing.
actor CrowdShieldAuthService {
    static let shared = CrowdShieldAuthService()

    private let session = URLSession.shared

    /// Registers a new account. The user lands in Cognito unconfirmed until
    /// `confirmSignUp` succeeds with the emailed code — at that point the
    /// PostConfirmation Lambda trigger (backend) automatically adds them to
    /// the "Public" group, so no group assignment happens client-side.
    func signUp(email: String, password: String) async throws {
        let body: [String: Any] = [
            "ClientId": CrowdShieldConfig.userPoolClientId,
            "Username": email,
            "Password": password,
            "UserAttributes": [
                ["Name": "email", "Value": email]
            ],
        ]
        _ = try await call(target: "SignUp", body: body)
    }

    /// Confirms a signup using the code Cognito emails to the address. On
    /// success the account is fully active and the PostConfirmation trigger
    /// has already run server-side, so `signIn` immediately after this call
    /// will return a token with the Public group present.
    func confirmSignUp(email: String, code: String) async throws {
        let body: [String: Any] = [
            "ClientId": CrowdShieldConfig.userPoolClientId,
            "Username": email,
            "ConfirmationCode": code,
        ]
        _ = try await call(target: "ConfirmSignUp", body: body)
    }

    /// Re-sends the confirmation code, for the case where the first email
    /// didn't arrive or the code expired before the user entered it.
    func resendConfirmationCode(email: String) async throws {
        let body: [String: Any] = [
            "ClientId": CrowdShieldConfig.userPoolClientId,
            "Username": email,
        ]
        _ = try await call(target: "ResendConfirmationCode", body: body)
    }

    /// Starts the "forgot password" flow — Cognito emails a confirmation
    /// code to the account's address. Call `confirmForgotPassword` with
    /// that code and the new password to complete the reset. Cognito
    /// deliberately doesn't distinguish "no such user" from "code sent" in
    /// its default response here (to avoid leaking which emails have
    /// accounts), so a successful call doesn't guarantee the email exists —
    /// the UI should say "if an account exists, a code was sent" rather
    /// than confirming existence either way.
    func forgotPassword(email: String) async throws {
        let body: [String: Any] = [
            "ClientId": CrowdShieldConfig.userPoolClientId,
            "Username": email,
        ]
        _ = try await call(target: "ForgotPassword", body: body)
    }

    /// Completes a password reset using the code emailed by
    /// `forgotPassword`. On success the new password is active immediately
    /// — the caller should follow this with a normal `signIn` using the
    /// new password, since ConfirmForgotPassword doesn't itself return
    /// tokens.
    func confirmForgotPassword(email: String, code: String, newPassword: String) async throws {
        let body: [String: Any] = [
            "ClientId": CrowdShieldConfig.userPoolClientId,
            "Username": email,
            "ConfirmationCode": code,
            "Password": newPassword,
        ]
        _ = try await call(target: "ConfirmForgotPassword", body: body)
    }

    /// Signs in with USER_PASSWORD_AUTH. If Cognito responds with the
    /// NEW_PASSWORD_REQUIRED challenge (e.g. for a freshly console-created
    /// user), this throws `.newPasswordRequired(session:)` so the caller can
    /// present a "set new password" step and call `completeNewPassword`.
    func signIn(email: String, password: String) async throws -> AuthSession {
        let body: [String: Any] = [
            "AuthFlow": "USER_PASSWORD_AUTH",
            "ClientId": CrowdShieldConfig.userPoolClientId,
            "AuthParameters": [
                "USERNAME": email,
                "PASSWORD": password,
            ],
        ]

        let json = try await call(target: "InitiateAuth", body: body)

        if let challenge = json["ChallengeName"] as? String, challenge == "NEW_PASSWORD_REQUIRED" {
            guard let session = json["Session"] as? String else {
                throw AuthError.unexpectedResponse("Missing session for password challenge.")
            }
            throw AuthError.newPasswordRequired(session: session)
        }

        return try decodeAuthenticationResult(from: json, email: email)
    }

    /// Completes a NEW_PASSWORD_REQUIRED challenge, setting a permanent
    /// password and returning a fully authenticated session — mirrors the
    /// RespondToAuthChallenge call used during manual backend testing.
    func completeNewPassword(email: String, newPassword: String, session: String) async throws -> AuthSession {
        let body: [String: Any] = [
            "ChallengeName": "NEW_PASSWORD_REQUIRED",
            "ClientId": CrowdShieldConfig.userPoolClientId,
            "Session": session,
            "ChallengeResponses": [
                "USERNAME": email,
                "NEW_PASSWORD": newPassword,
            ],
        ]

        let json = try await call(target: "RespondToAuthChallenge", body: body)
        return try decodeAuthenticationResult(from: json, email: email)
    }

    /// Exchanges a refresh token for a fresh IdToken/AccessToken pair,
    /// avoiding a full re-login once the 1-hour token validity expires.
    func refresh(refreshToken: String, email: String) async throws -> AuthSession {
        let body: [String: Any] = [
            "AuthFlow": "REFRESH_TOKEN_AUTH",
            "ClientId": CrowdShieldConfig.userPoolClientId,
            "AuthParameters": [
                "REFRESH_TOKEN": refreshToken
            ],
        ]

        let json = try await call(target: "InitiateAuth", body: body)
        // Refresh responses omit RefreshToken (the original stays valid), so
        // decodeAuthenticationResult falls back to the one we already have.
        return try decodeAuthenticationResult(from: json, email: email, fallbackRefreshToken: refreshToken)
    }

    // MARK: - Private

    private func call(target: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: CrowdShieldConfig.cognitoIdpURL)
        request.httpMethod = "POST"
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue("AWSCognitoIdentityProviderService.\(target)", forHTTPHeaderField: "X-Amz-Target")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AuthError.network(underlying: error)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.unexpectedResponse("Malformed response from Cognito.")
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            let type = json["__type"] as? String ?? ""
            let message = json["message"] as? String ?? "Request failed."

            if type.contains("NotAuthorizedException") || type.contains("UserNotFoundException") {
                throw AuthError.invalidCredentials
            }
            if type.contains("UsernameExistsException") {
                throw AuthError.usernameExists
            }
            if type.contains("CodeMismatchException") || type.contains("ExpiredCodeException") {
                throw AuthError.invalidConfirmationCode
            }
            if type.contains("InvalidPasswordException") {
                throw AuthError.weakPassword(message)
            }
            throw AuthError.unexpectedResponse(message)
        }

        return json
    }

    private func decodeAuthenticationResult(
        from json: [String: Any],
        email: String,
        fallbackRefreshToken: String? = nil
    ) throws -> AuthSession {
        guard let result = json["AuthenticationResult"] as? [String: Any],
              let idToken = result["IdToken"] as? String,
              let accessToken = result["AccessToken"] as? String
        else {
            throw AuthError.unexpectedResponse("Missing AuthenticationResult in Cognito response.")
        }

        let refreshToken = (result["RefreshToken"] as? String) ?? fallbackRefreshToken ?? ""
        let groups = Self.groups(fromIdToken: idToken)

        return AuthSession(
            idToken: idToken,
            accessToken: accessToken,
            refreshToken: refreshToken,
            groups: groups,
            email: email
        )
    }

    /// Decodes the JWT's payload segment (no signature verification — the
    /// token is only trusted because it just came directly from Cognito over
    /// HTTPS in this same call) to read the `cognito:groups` claim.
    private static func groups(fromIdToken idToken: String) -> [String] {
        let segments = idToken.split(separator: ".")
        guard segments.count >= 2 else { return [] }

        var base64 = String(segments[1])
        base64 = base64.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }

        guard let payloadData = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else {
            return []
        }

        if let groupsArray = payload["cognito:groups"] as? [String] {
            return groupsArray
        }
        return []
    }
}
