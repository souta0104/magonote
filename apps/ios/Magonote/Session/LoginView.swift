import SwiftUI
import UIKit

struct LoginView: View {
  @Environment(SessionStore.self) private var session
  @State private var isSigningIn = false
  @State private var errorMessage: String?

  var body: some View {
    VStack(spacing: 24) {
      Image(systemName: "text.book.closed.fill")
        .font(.system(size: 64))
        .foregroundStyle(.tint)

      VStack(spacing: 8) {
        Text("Magonote Reader")
          .font(.title.bold())
        Text("Mac で保存したテキストを、読みやすい画面で確認できます。")
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }

      Button {
        Task {
          await signIn()
        }
      } label: {
        HStack {
          if isSigningIn {
            ProgressView()
          }
          Text("Google でログイン")
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .disabled(isSigningIn)
    }
    .padding(32)
    .alert(
      "ログインできませんでした",
      isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )
    ) {
      Button("閉じる", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "不明なエラーです")
    }
  }

  private func signIn() async {
    isSigningIn = true
    defer { isSigningIn = false }

    do {
      guard let presenter = UIApplication.shared.magonoteRootViewController else {
        throw SessionError.presentingViewControllerUnavailable
      }
      try await session.signIn(presenting: presenter)
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

extension UIApplication {
  fileprivate var magonoteRootViewController: UIViewController? {
    connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)?
      .rootViewController
  }
}
