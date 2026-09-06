import Foundation

/// Backend configuration for the CrowdShield AWS deployment (Phase 1 + 2).
///
/// These values come from the CloudFormation stack Outputs
/// (`crowdshield-phase1` in `ap-south-2`). If you redeploy to a new stack,
/// region, or environment name, update the values here — nothing else in
/// the app should need to change.
/// Explicitly `nonisolated`: this project sets
/// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor at the build-settings level,
/// which implicitly isolates every type (including plain enums like this
/// one) to the main actor unless opted out. CrowdShieldConfig is read from
/// several non-MainActor contexts that do real network I/O off the main
/// thread (CrowdShieldAPIClient, CrowdShieldAuthService,
/// CrowdShieldRealtimeClient) — it holds only immutable constants, so
/// there's no actual data-race risk in accessing it from any thread, and
/// forcing those reads through the main actor would serve no purpose.
nonisolated enum CrowdShieldConfig {
    /// Base URL for the HTTP API, no trailing slash.
    /// Stack output: ApiEndpoint
    static let apiBaseURL = URL(string: "https://n4adcwp1zb.execute-api.ap-south-2.amazonaws.com/dev")!

    /// Cognito User Pool ID.
    /// Stack output: UserPoolId
    static let userPoolId = "ap-south-2_SW6Ca9IHs"

    /// Cognito App Client ID (no secret — public client for the iOS app).
    /// Stack output: UserPoolClientId
    static let userPoolClientId = "4nr24ai9rodv9nbhk7973otv6g"

    /// Cognito's regional IdP endpoint used for InitiateAuth / RespondToAuthChallenge.
    static let cognitoIdpURL = URL(string: "https://cognito-idp.ap-south-2.amazonaws.com/")!

    /// The venue this prototype operates against. A real multi-venue
    /// deployment would make this dynamic (selected at sign-in or via
    /// location), but Phase 1/2 provisioned a single default venue.
    static let defaultVenueId = "technova-festival-grounds"

    /// WebSocket API for real-time push (Phase 4).
    /// Stack output: WebSocketUrl
    static let webSocketURL = URL(string: "wss://jddr0nrr9l.execute-api.ap-south-2.amazonaws.com/dev")!
}
