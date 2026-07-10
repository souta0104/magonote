import Foundation

/// Provides the caller's Firebase ID token for authenticating requests to the
/// magonote API. Each app (iOS / macOS) implements this using its own
/// Firebase SDK integration; MagonoteKit stays free of Firebase dependencies
/// (dependency inversion).
public protocol AuthTokenProvider: Sendable {
    func idToken() async throws -> String
}
