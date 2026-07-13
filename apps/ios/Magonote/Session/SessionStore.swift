import FirebaseAuth
import GoogleSignIn
import MagonoteKit
import Observation
import UIKit

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

  func signIn(presenting viewController: UIViewController) async throws {
    let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
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
}

enum SessionError: LocalizedError {
  case presentingViewControllerUnavailable
  case googleIDTokenUnavailable

  var errorDescription: String? {
    switch self {
    case .presentingViewControllerUnavailable:
      "Google ログインを表示する画面が見つかりません"
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
