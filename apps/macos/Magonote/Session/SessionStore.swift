import AppKit
import FirebaseAuth
import GoogleSignIn
import MagonoteKit
import Observation

@MainActor
@Observable
final class SessionStore {
    private(set) var user: User?
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    var isSignedIn: Bool {
        user != nil
    }

    var emailAddress: String? {
        user?.email
    }

    var uid: String? {
        user?.uid
    }

    func start() {
        guard authStateHandle == nil else {
            return
        }

        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
            }
        }
    }

    func signIn() async throws {
        NSApp.activate(ignoringOtherApps: true)

        guard let window = NSApp.keyWindow ?? NSApp.windows.first else {
            throw SessionError.presentingWindowUnavailable
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: window)
        guard let idToken = result.user.idToken?.tokenString else {
            throw SessionError.googleIDTokenUnavailable
        }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        _ = try await Auth.auth().signIn(with: credential)
    }

    func signOut() throws {
        try Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
    }

    func resetSession() throws {
        try signOut()
        user = nil
    }
}

enum SessionError: LocalizedError {
    case presentingWindowUnavailable
    case googleIDTokenUnavailable

    var errorDescription: String? {
        switch self {
        case .presentingWindowUnavailable:
            "Google ログインを表示するウィンドウが見つかりません"
        case .googleIDTokenUnavailable:
            "Google から ID token を取得できませんでした"
        }
    }
}

struct FirebaseAuthTokenProvider: AuthTokenProvider {
    func idToken() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw APIError.unauthorized
        }

        return try await user.getIDToken()
    }
}
